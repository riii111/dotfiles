import subprocess
import tempfile
import unittest
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BR_SCRIPT = ROOT / "bin" / "executable_git-prune-gone-br"
WT_SCRIPT = ROOT / "bin" / "executable_git-prune-gone-wt"


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

    def create_tracked_branch(self, name):
        self.git("checkout", "-b", name)
        self.commit_file(f"{name}.txt", f"{name}\n", name)
        self.git("push", "-u", "origin", name)

    def delete_remote_branch(self, name):
        self.git("push", "origin", "--delete", name)

    def run_script(self, script, *args):
        env = os.environ.copy()
        env["NO_COLOR"] = "1"
        return subprocess.run(
            ["python3", str(script), *args],
            cwd=self.repo,
            text=True,
            capture_output=True,
            check=False,
            env=env,
        )

    def run_script_outside_repo(self, script, *args):
        env = os.environ.copy()
        env["NO_COLOR"] = "1"
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
        self.assertIn("Would remove (branch): remove-me", dry_run.stdout)
        self.assertIn("Skipped (worktree): worktree-branch", dry_run.stdout)
        self.assertIn("Summary: 1 would remove, 1 skipped", dry_run.stdout)

        result = self.run_script(BR_SCRIPT)

        self.assertEqual(result.returncode, 0)
        self.assertIn("Removed (branch): remove-me", result.stdout)
        self.assertIn("Skipped (worktree): worktree-branch", result.stdout)
        self.assertIn("Summary: 1 removed, 1 skipped", result.stdout)
        self.assertEqual(self.git("branch", "--list", "remove-me"), "")
        self.assertIn("worktree-branch", self.git("branch", "--list", "worktree-branch"))

    def test_branch_script_reports_no_gone_branches(self):
        result = self.run_script(BR_SCRIPT)

        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "No gone branches found")

    def test_worktree_script_removes_only_worktree(self):
        self.create_tracked_branch("gone-worktree")
        self.git("checkout", "main")
        worktree_path = self.root / "gone-worktree"
        self.git("worktree", "add", str(worktree_path), "gone-worktree")
        self.delete_remote_branch("gone-worktree")

        dry_run = self.run_script(WT_SCRIPT, "--dry-run")
        self.assertEqual(dry_run.returncode, 0)
        self.assertIn("Would remove (worktree): gone-worktree", dry_run.stdout)
        self.assertIn("Summary: 1 would remove, 0 skipped", dry_run.stdout)
        self.assertIn("Hint: branches still exist. Run `git prune-gone-br` to remove them.", dry_run.stdout)
        self.assertTrue(worktree_path.exists())

        result = self.run_script(WT_SCRIPT)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Removed (worktree): gone-worktree", result.stdout)
        self.assertIn("Summary: 1 removed, 0 skipped", result.stdout)
        self.assertIn("Hint: branches still exist. Run `git prune-gone-br` to remove them.", result.stdout)
        self.assertFalse(worktree_path.exists())
        self.assertIn("gone-worktree", self.git("branch", "--list", "gone-worktree"))

    def test_worktree_script_skips_dirty_worktree(self):
        self.create_tracked_branch("dirty-worktree")
        self.git("checkout", "main")
        worktree_path = self.root / "dirty-worktree"
        self.git("worktree", "add", str(worktree_path), "dirty-worktree")
        self.delete_remote_branch("dirty-worktree")
        (worktree_path / "dirty.txt").write_text("dirty\n", encoding="utf-8")

        result = self.run_script(WT_SCRIPT, "--dry-run")

        self.assertEqual(result.returncode, 0)
        self.assertIn("Skipped (dirty): dirty-worktree", result.stdout)
        self.assertTrue(worktree_path.exists())

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
