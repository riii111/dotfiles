import importlib.util
import json
import io
import subprocess
import tempfile
import unittest
import os
from pathlib import Path
from importlib.machinery import SourceFileLoader
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
BR_SCRIPT = ROOT / "bin" / "executable_git-prune-gone-br"
WT_SCRIPT = ROOT / "bin" / "executable_git-prune-gone-wt"


def load_script_module(name, path):
    loader = SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class GitPruneGoneTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.origin = self.root / "origin.git"
        self.repo = self.root / "repo"
        subprocess.run(["git", "init", "--bare", self.origin], check=True)
        subprocess.run(["git", "clone", self.origin, self.repo], check=True)
        self.git("checkout", "-b", "main")
        self.git("config", "user.name", "Test User")
        self.git("config", "user.email", "test@example.com")
        self.commit_file("root.txt", "root\n", "root")
        self.git("push", "-u", "origin", "main")

    def tearDown(self):
        self.tempdir.cleanup()

    def git(self, *args, cwd=None):
        return subprocess.check_output(
            ["git", *args],
            cwd=cwd or self.repo,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()

    def commit_file(self, name, content, message, cwd=None):
        path = (cwd or self.repo) / name
        path.write_text(content, encoding="utf-8")
        self.git("add", name, cwd=cwd)
        self.git("commit", "-m", message, cwd=cwd)

    def load_wt_module(self):
        return load_script_module(self.id(), WT_SCRIPT)

    def create_tracked_branch(self, name):
        self.git("checkout", "-b", name)
        self.commit_file(f"{name}.txt", f"{name}\n", name)
        self.git("push", "-u", "origin", name)

    def delete_remote_branch(self, name):
        self.git("push", "origin", "--delete", name)

    def create_gone_worktree(self, name, worktree_dir=None):
        self.create_tracked_branch(name)
        self.git("checkout", "main")
        worktree_path = (worktree_dir or self.root) / name
        self.git("worktree", "add", str(worktree_path), name)
        self.delete_remote_branch(name)
        return worktree_path

    def set_origin_head(self, branch="main"):
        subprocess.run(
            [
                "git",
                "symbolic-ref",
                "refs/remotes/origin/HEAD",
                f"refs/remotes/origin/{branch}",
            ],
            cwd=self.repo,
            check=True,
        )

    def run_script(self, script, *args, extra_env=None, cwd=None):
        env = os.environ.copy()
        env["NO_COLOR"] = "1"
        if extra_env:
            env.update(extra_env)
        return subprocess.run(
            ["python3", str(script), *args],
            cwd=cwd or self.repo,
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )

    def run_script_outside_repo(self, script, *args, extra_env=None):
        env = os.environ.copy()
        env["NO_COLOR"] = "1"
        if extra_env:
            env.update(extra_env)
        outside = self.root / "outside"
        outside.mkdir(exist_ok=True)
        return subprocess.run(
            ["python3", str(script), *args],
            cwd=outside,
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )

    def test_branch_script_deletes_gone_branch_and_skips_worktree_branch(self):
        self.create_tracked_branch("remove-me")
        self.git("checkout", "main")
        self.delete_remote_branch("remove-me")

        self.create_tracked_branch("worktree-branch")
        self.git("checkout", "main")
        worktree_path = self.root / "worktree-branch"
        self.git("worktree", "add", str(worktree_path), "worktree-branch")
        self.delete_remote_branch("worktree-branch")

        dry_run = self.run_script(BR_SCRIPT, "--dry-run")
        self.assertEqual(dry_run.returncode, 0)
        self.assertIn("Would remove (gone branch): remove-me", dry_run.stdout)
        self.assertIn("Skipped (worktree): worktree-branch", dry_run.stdout)
        self.assertIn("Summary: 1 would remove, 1 skipped", dry_run.stdout)

        result = self.run_script(BR_SCRIPT)

        self.assertEqual(result.returncode, 0)
        self.assertIn("Removed (gone branch): remove-me", result.stdout)
        self.assertIn("Skipped (worktree): worktree-branch", result.stdout)
        self.assertIn("Summary: 1 removed, 1 skipped", result.stdout)
        self.assertEqual(self.git("branch", "--list", "remove-me"), "")
        self.assertIn(
            "worktree-branch", self.git("branch", "--list", "worktree-branch")
        )

    def test_branch_script_removes_merged_local_branch_without_upstream(self):
        self.git("checkout", "-b", "merged-local")
        self.commit_file("merged-local.txt", "merged-local\n", "merged-local")
        self.git("checkout", "main")
        self.git("merge", "--ff-only", "merged-local")

        dry_run = self.run_script(BR_SCRIPT, "--dry-run")

        self.assertEqual(dry_run.returncode, 0)
        self.assertIn("Would remove (merged branch): merged-local", dry_run.stdout)

        result = self.run_script(BR_SCRIPT)

        self.assertEqual(result.returncode, 0)
        self.assertIn("Removed (merged branch): merged-local", result.stdout)
        self.assertEqual(self.git("branch", "--list", "merged-local"), "")

    def test_branch_script_uses_local_main_when_origin_head_is_stale(self):
        self.git("checkout", "-b", "merged-local")
        self.commit_file("merged-local.txt", "merged-local\n", "merged-local")
        self.git("checkout", "main")
        self.git("merge", "--ff-only", "merged-local")
        self.set_origin_head("master")

        result = self.run_script(BR_SCRIPT, "--dry-run")

        self.assertEqual(result.returncode, 0)
        self.assertIn("Would remove (merged branch): merged-local", result.stdout)

    def test_branch_script_uses_origin_head_when_local_default_branch_is_missing(self):
        self.git("checkout", "-b", "current-feature")
        self.git("checkout", "main")
        self.git("checkout", "-b", "merged-local")
        self.commit_file("merged-local.txt", "merged-local\n", "merged-local")
        self.git("checkout", "main")
        self.git("merge", "--ff-only", "merged-local")
        self.git("push", "origin", "main")
        self.git("checkout", "current-feature")
        self.git("branch", "-D", "main")
        self.set_origin_head("main")

        result = self.run_script(BR_SCRIPT, "--dry-run", "--no-fetch")

        self.assertEqual(result.returncode, 0)
        self.assertIn("Would remove (merged branch): merged-local", result.stdout)

    def test_branch_script_reports_no_stale_branches(self):
        result = self.run_script(BR_SCRIPT)

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No stale branches found")

    def test_branch_script_removes_orphan_slot_branch(self):
        self.git("checkout", "-b", "_slot-abc123")
        self.commit_file("slot.txt", "slot\n", "slot")
        self.git("checkout", "main")

        result = self.run_script(BR_SCRIPT, "--dry-run", "--no-fetch")

        self.assertEqual(result.returncode, 0)
        self.assertIn("Would remove (orphan slot branch): _slot-abc123", result.stdout)

    def test_branch_script_ignores_non_stale_worktree_branch(self):
        self.create_tracked_branch("active-worktree-branch")
        self.git("checkout", "main")
        worktree_path = self.root / "active-worktree-branch"
        self.git("worktree", "add", str(worktree_path), "active-worktree-branch")

        result = self.run_script(BR_SCRIPT, "--dry-run", "--no-fetch")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No stale branches found")

    def test_branch_script_skips_fetch_when_no_fetch_is_set(self):
        self.git("remote", "set-url", "origin", "ssh://invalid.example/repo.git")

        result = self.run_script(BR_SCRIPT, "--dry-run", "--no-fetch")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No stale branches found")

    def test_worktree_script_removes_only_worktree(self):
        worktree_path = self.create_gone_worktree("gone-worktree")

        dry_run = self.run_script(WT_SCRIPT, "--dry-run")
        self.assertEqual(dry_run.returncode, 0)
        self.assertIn(
            "Would remove (gone branch worktree): gone-worktree", dry_run.stdout
        )
        self.assertIn("Summary: 1 would remove, 0 skipped", dry_run.stdout)
        self.assertIn(
            "Hint: branches still exist. Run `git prune-gone-br` to remove them.",
            dry_run.stdout,
        )
        self.assertTrue(worktree_path.exists())

        result = self.run_script(WT_SCRIPT)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Removed (gone branch worktree): gone-worktree", result.stdout)
        self.assertIn("Summary: 1 removed, 0 skipped", result.stdout)
        self.assertIn(
            "Hint: branches still exist. Run `git prune-gone-br` to remove them.",
            result.stdout,
        )
        self.assertFalse(worktree_path.exists())
        self.assertIn("gone-worktree", self.git("branch", "--list", "gone-worktree"))

    def test_worktree_script_skips_dirty_worktree(self):
        worktree_path = self.create_gone_worktree("dirty-worktree")
        (worktree_path / "dirty.txt").write_text("dirty\n", encoding="utf-8")

        result = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(result.returncode, 0)
        self.assertIn("Skipped (dirty): dirty-worktree", result.stdout)
        self.assertTrue(worktree_path.exists())

    def test_worktree_script_skips_locked_worktree(self):
        worktree_path = self.create_gone_worktree("locked-worktree")
        self.git("worktree", "lock", str(worktree_path))

        result = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(result.returncode, 0)
        self.assertIn("Skipped (locked): locked-worktree", result.stdout)
        self.assertTrue(worktree_path.exists())

    def test_worktree_script_prunes_prunable_worktree(self):
        self.create_tracked_branch("prunable-worktree")
        self.git("checkout", "main")
        worktree_path = self.root / "prunable-worktree"
        self.git("worktree", "add", str(worktree_path), "prunable-worktree")
        subprocess.run(["rm", "-rf", str(worktree_path)], check=True)

        dry_run = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(dry_run.returncode, 0)
        self.assertIn("Would prune (worktree): prunable-worktree", dry_run.stdout)

        result = self.run_script(WT_SCRIPT)

        self.assertEqual(result.returncode, 0)
        self.assertIn("Pruned (worktree): prunable-worktree", result.stdout)
        self.assertNotIn(
            str(worktree_path), self.git("worktree", "list", "--porcelain")
        )

    def test_worktree_script_removes_merged_codex_branch_worktree(self):
        self.git("checkout", "-b", "merged-codex")
        self.commit_file("merged-codex.txt", "merged-codex\n", "merged-codex")
        self.git("checkout", "main")
        self.git("merge", "--ff-only", "merged-codex")

        worktree_path = self.repo / ".codex" / "worktrees" / "merged-codex"
        worktree_path.parent.mkdir(parents=True, exist_ok=True)
        self.git("worktree", "add", str(worktree_path), "merged-codex")

        dry_run = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(dry_run.returncode, 0)
        self.assertIn(
            "Would remove (merged branch worktree): merged-codex", dry_run.stdout
        )
        self.assertIn(
            "Hint: branches still exist. Run `git prune-gone-br` to remove them.",
            dry_run.stdout,
        )

        result = self.run_script(WT_SCRIPT)

        self.assertEqual(result.returncode, 0)
        self.assertIn("Removed (merged branch worktree): merged-codex", result.stdout)
        self.assertIn(
            "Hint: branches still exist. Run `git prune-gone-br` to remove them.",
            result.stdout,
        )
        self.assertNotIn(
            str(worktree_path), self.git("worktree", "list", "--porcelain")
        )

    def test_worktree_script_uses_local_main_when_origin_head_is_stale(self):
        self.git("checkout", "-b", "merged-codex")
        self.commit_file("merged-codex.txt", "merged-codex\n", "merged-codex")
        self.git("checkout", "main")
        self.git("merge", "--ff-only", "merged-codex")
        self.set_origin_head("master")

        worktree_path = self.repo / ".codex" / "worktrees" / "merged-codex"
        worktree_path.parent.mkdir(parents=True, exist_ok=True)
        self.git("worktree", "add", str(worktree_path), "merged-codex")

        result = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(result.returncode, 0)
        self.assertIn(
            "Would remove (merged branch worktree): merged-codex", result.stdout
        )

    def test_worktree_script_uses_origin_head_when_local_default_branch_is_missing(
        self,
    ):
        self.git("checkout", "-b", "current-feature")
        self.git("checkout", "main")
        self.git("checkout", "-b", "merged-codex")
        self.commit_file("merged-codex.txt", "merged-codex\n", "merged-codex")
        self.git("checkout", "main")
        self.git("merge", "--ff-only", "merged-codex")
        self.git("push", "origin", "main")
        self.git("checkout", "current-feature")
        self.git("branch", "-D", "main")
        self.set_origin_head("main")

        worktree_path = self.repo / ".codex" / "worktrees" / "merged-codex"
        worktree_path.parent.mkdir(parents=True, exist_ok=True)
        self.git("worktree", "add", str(worktree_path), "merged-codex")

        result = self.run_script(WT_SCRIPT, "--dry-run", "--no-fetch")

        self.assertEqual(result.returncode, 0)
        self.assertIn(
            "Would remove (merged branch worktree): merged-codex", result.stdout
        )

    def test_worktree_script_keeps_unmerged_codex_branch_worktree(self):
        self.git("checkout", "-b", "active-codex")
        self.commit_file("active-codex.txt", "active-codex\n", "active-codex")
        self.git("checkout", "main")

        worktree_path = self.repo / ".codex" / "worktrees" / "active-codex"
        worktree_path.parent.mkdir(parents=True, exist_ok=True)
        self.git("worktree", "add", str(worktree_path), "active-codex")

        result = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No gone worktrees found")

    def test_worktree_script_keeps_open_pr_review_worktree(self):
        worktree_path = self.root / f"{self.repo.name}-pr-123"
        self.git("worktree", "add", "--detach", str(worktree_path), "HEAD")

        result = self.run_script(
            WT_SCRIPT,
            "--dry-run",
            extra_env={"PRUNE_GONE_WT_PR_STATES": "123:OPEN"},
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("Skipped (open pr): repo-pr-123", result.stdout)

    def test_worktree_script_keeps_detached_managed_worktree(self):
        worktree_path = self.repo / ".codex" / "worktrees" / "detached-codex"
        worktree_path.parent.mkdir(parents=True, exist_ok=True)
        self.git("worktree", "add", "--detach", str(worktree_path), "HEAD")

        result = self.run_script(WT_SCRIPT, "--dry-run", "--no-fetch")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No gone worktrees found")

    def test_worktree_script_removes_closed_pr_review_worktree(self):
        worktree_path = self.root / f"{self.repo.name}-pr-123"
        self.git("worktree", "add", "--detach", str(worktree_path), "HEAD")

        dry_run = self.run_script(
            WT_SCRIPT,
            "--dry-run",
            extra_env={"PRUNE_GONE_WT_PR_STATES": "123:CLOSED"},
        )

        self.assertEqual(dry_run.returncode, 0)
        self.assertIn("Would remove (closed pr worktree): repo-pr-123", dry_run.stdout)

        result = self.run_script(
            WT_SCRIPT,
            extra_env={"PRUNE_GONE_WT_PR_STATES": "123:CLOSED"},
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn("Removed (closed pr worktree): repo-pr-123", result.stdout)
        self.assertNotIn(
            str(worktree_path), self.git("worktree", "list", "--porcelain")
        )

    def test_worktree_script_finds_candidates_when_run_from_linked_worktree(self):
        self.git("checkout", "-b", "current-linked")
        self.git("checkout", "main")
        runner_path = self.root / "runner"
        self.git("worktree", "add", str(runner_path), "current-linked")

        self.git("checkout", "-b", "merged-codex")
        self.commit_file("merged-codex.txt", "merged-codex\n", "merged-codex")
        self.git("checkout", "main")
        self.git("merge", "--ff-only", "merged-codex")
        worktree_path = self.repo / ".codex" / "worktrees" / "merged-codex"
        worktree_path.parent.mkdir(parents=True, exist_ok=True)
        self.git("worktree", "add", str(worktree_path), "merged-codex")

        review_path = self.root / f"{self.repo.name}-pr-123"
        self.git("worktree", "add", "--detach", str(review_path), "HEAD")

        result = self.run_script(
            WT_SCRIPT,
            "--dry-run",
            "--no-fetch",
            extra_env={"PRUNE_GONE_WT_PR_STATES": "123:CLOSED"},
            cwd=runner_path,
        )

        self.assertEqual(result.returncode, 0)
        self.assertIn(
            "Would remove (merged branch worktree): merged-codex", result.stdout
        )
        self.assertIn("Would remove (closed pr worktree): repo-pr-123", result.stdout)

    def test_worktree_script_skips_fetch_when_no_fetch_is_set(self):
        self.git("remote", "set-url", "origin", "ssh://invalid.example/repo.git")

        result = self.run_script(WT_SCRIPT, "--dry-run", "--no-fetch")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No gone worktrees found")

    def test_worktree_script_batches_pr_state_queries(self):
        module = self.load_wt_module()
        calls = []

        def fake_run(args, **kwargs):
            calls.append(args)
            if args[:5] == [
                "gh",
                "auth",
                "token",
                "--hostname",
                "github.com",
            ]:
                return subprocess.CompletedProcess(args, 0, stdout="token\n", stderr="")
            if args[:3] == ["gh", "api", "graphql"]:
                self.assertIn("pr123: pullRequest(number: 123)", args[-1])
                self.assertIn("pr456: pullRequest(number: 456)", args[-1])
                payload = {
                    "data": {
                        "repository": {
                            "pr123": {"state": "OPEN"},
                            "pr456": {"state": "MERGED"},
                        }
                    }
                }
                return subprocess.CompletedProcess(
                    args,
                    0,
                    stdout=os.linesep.join([json.dumps(payload)]),
                    stderr="",
                )
            self.fail(f"unexpected subprocess.run call: {args}")

        with (
            mock.patch.object(module, "parse_origin_repo", return_value=("o", "r")),
            mock.patch.object(module, "gh_auth_users", return_value=["tester"]),
            mock.patch.object(module.subprocess, "run", side_effect=fake_run),
        ):
            states = module.pr_states([123, 456, 123])

        self.assertEqual(states, {123: "OPEN", 456: "MERGED"})
        graphql_calls = [args for args in calls if args[:3] == ["gh", "api", "graphql"]]
        self.assertEqual(len(graphql_calls), 1)

    def test_worktree_script_reads_github_users_from_json_status(self):
        module = self.load_wt_module()
        payload = {
            "hosts": {
                "github.com": [
                    {"login": "riii111", "active": True},
                    {"login": "ichinose_sansan", "active": False},
                ]
            }
        }

        with mock.patch.object(
            module.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                ["gh", "auth", "status", "--json", "hosts"],
                0,
                stdout=json.dumps(payload),
                stderr="",
            ),
        ):
            users = module.gh_auth_users()

        self.assertEqual(users, ["riii111", "ichinose_sansan"])

    def test_worktree_script_warns_when_pr_state_lookup_fails(self):
        module = self.load_wt_module()
        stderr = io.StringIO()

        with (
            mock.patch.object(module, "parse_origin_repo", return_value=("o", "r")),
            mock.patch.object(module, "gh_auth_users", return_value=["tester"]),
            mock.patch.object(
                module.subprocess,
                "run",
                side_effect=[
                    subprocess.CompletedProcess(
                        ["gh", "auth", "token"], 1, stdout="", stderr="boom"
                    )
                ],
            ),
            mock.patch("sys.stderr", stderr),
        ):
            states = module.pr_states([123])

        self.assertEqual(states, {})
        self.assertIn(
            "Warning: could not fetch PR states from GitHub", stderr.getvalue()
        )

    def test_worktree_script_parses_origin_repo_urls(self):
        module = self.load_wt_module()

        with mock.patch.object(
            module, "git_output", return_value="git@github.com:owner/repo.git"
        ):
            self.assertEqual(module.parse_origin_repo(), ("owner", "repo"))

        with mock.patch.object(
            module,
            "git_output",
            return_value="git@github.com-riii111:owner/repo.git",
        ):
            self.assertEqual(module.parse_origin_repo(), ("owner", "repo"))

        with mock.patch.object(
            module, "git_output", return_value="https://github.com/owner/repo"
        ):
            self.assertEqual(module.parse_origin_repo(), ("owner", "repo"))

        with mock.patch.object(
            module, "git_output", return_value="https://gitlab.com/owner/repo"
        ):
            self.assertIsNone(module.parse_origin_repo())

    def test_worktree_script_reports_no_gone_worktrees(self):
        result = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No gone worktrees found")

    def test_scripts_report_friendly_error_outside_repo(self):
        br_result = self.run_script_outside_repo(BR_SCRIPT)
        wt_result = self.run_script_outside_repo(WT_SCRIPT)

        self.assertEqual(br_result.returncode, 1)
        self.assertEqual(wt_result.returncode, 1)
        self.assertIn("Error: `git fetch --prune --quiet` failed", br_result.stderr)
        self.assertIn("Error: `git fetch --prune --quiet` failed", wt_result.stderr)
        self.assertNotIn("Traceback", br_result.stderr)
        self.assertNotIn("Traceback", wt_result.stderr)


if __name__ == "__main__":
    unittest.main()
