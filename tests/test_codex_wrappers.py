import importlib.machinery
import importlib.util
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
READ_LINES = ROOT / "bin" / "executable_codex-read-lines"
FORCE_WITH_LEASE = ROOT / "bin" / "executable_codex-force-with-lease"
OUTSIDE_ROOT = "file is outside an approved root"
UNTRUSTED_CHECKOUT = "current repository is not a trusted GitHub checkout"


def load_script(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_wrapper(filename="executable_codex-force-with-lease"):
    path = ROOT / "bin" / filename
    return load_script(path, filename.replace("-", "_"))


git_trust = load_wrapper().git_trust


class GitTrustTest(unittest.TestCase):
    def test_https_alias_is_not_a_github_host(self):
        with mock.patch.object(
            git_trust, "github_host", side_effect=lambda host: host == "work-github"
        ):
            self.assertIsNone(
                git_trust.github_repository("https://work-github/riii111/test.git")
            )
            self.assertIsNone(
                git_trust.github_repository("git@github.com:riii111/test.git")
            )
            self.assertEqual(
                git_trust.github_repository("git@work-github:riii111/test.git"),
                ("riii111", "test"),
            )
            self.assertEqual(
                git_trust.github_repository("ssh://work-github/riii111/test.git"),
                ("riii111", "test"),
            )

    def test_ssh_config_timeout_is_untrusted(self):
        modules = [
            git_trust,
            load_script(
                ROOT / "dot_codex/hooks/executable_permission_request.py",
                "permission_request_hook",
            ),
        ]
        for module in modules:
            with mock.patch.object(
                module.subprocess,
                "run",
                side_effect=subprocess.TimeoutExpired(["ssh", "-G"], 2),
            ):
                self.assertIs(module.github_host("github.com"), False)

    def test_github_ssh_endpoints(self):
        for host, port, trusted in (
            ("github.com", "22", True),
            ("ssh.github.com", "443", True),
            ("github.com", "443", False),
            ("example.com", "22", False),
        ):
            with (
                self.subTest(host=host, port=port),
                mock.patch.dict(os.environ, {"GIT_SSH_COMMAND": "untrusted"}),
                mock.patch.object(
                    git_trust.subprocess,
                    "run",
                    return_value=subprocess.CompletedProcess(
                        ["ssh", "-G", "work-github"],
                        0,
                        stdout=f"hostname {host}\nport {port}\n",
                        stderr="",
                    ),
                ) as run,
            ):
                self.assertEqual(git_trust.github_host("work-github"), trusted)
                self.assertFalse(
                    any(name.startswith("GIT_") for name in run.call_args.kwargs["env"])
                )
                self.assertEqual(run.call_args.kwargs["timeout"], 2)


class ForceWithLeaseTest(unittest.TestCase):
    def test_missing_remote_branch_is_not_created(self):
        module = load_wrapper()
        with (
            mock.patch.object(
                module.git_trust, "trusted_repository", return_value=ROOT
            ),
            mock.patch.object(
                module.git_trust,
                "run_git",
                side_effect=[
                    subprocess.CompletedProcess([], 0, stdout="feat/test\n", stderr=""),
                    subprocess.CompletedProcess([], 0, stdout="", stderr=""),
                ],
            ),
            mock.patch.object(sys, "argv", ["codex-force-with-lease"]),
            redirect_stderr(io.StringIO()) as stderr,
        ):
            self.assertEqual(module.main(), 1)
        self.assertEqual(
            stderr.getvalue(), "remote branch does not exist; refusing to create it\n"
        )

    def test_remote_change_is_reported_as_push_failure(self):
        module = load_wrapper()
        calls = []
        old_oid = "1" * 40
        local_oid = "2" * 40

        def fake_run_git(cwd, *args):
            calls.append(args)
            if args[:3] == ("symbolic-ref", "--quiet", "--short"):
                return subprocess.CompletedProcess(
                    args, 0, stdout="feat/test\n", stderr=""
                )
            if args[:3] == ("ls-remote", "--heads", "origin"):
                return subprocess.CompletedProcess(
                    args, 0, stdout=f"{old_oid}\trefs/heads/feat/test\n", stderr=""
                )
            if args[:3] == ("rev-parse", "--verify", "refs/heads/feat/test"):
                return subprocess.CompletedProcess(
                    args, 0, stdout=f"{local_oid}\n", stderr=""
                )
            if args[:2] == ("push", "origin"):
                return subprocess.CompletedProcess(
                    args, 1, stdout="", stderr="stale lease\n"
                )
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as directory:
            original_cwd = Path.cwd()
            os.chdir(directory)
            try:
                with (
                    mock.patch.object(
                        module.git_trust,
                        "trusted_repository",
                        return_value=Path(directory),
                    ),
                    mock.patch.object(
                        module.git_trust, "run_git", side_effect=fake_run_git
                    ),
                    mock.patch.object(
                        sys,
                        "argv",
                        [str(ROOT / "bin" / "executable_codex-force-with-lease")],
                    ),
                    redirect_stderr(io.StringIO()),
                ):
                    self.assertEqual(module.main(), 1)
            finally:
                os.chdir(original_cwd)

        push = next(args for args in calls if args[:2] == ("push", "origin"))
        self.assertIn(
            f"--force-with-lease=refs/heads/feat/test:{old_oid}",
            push,
        )
        self.assertIn(f"{local_oid}:refs/heads/feat/test", push)


def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True)


class WrapperCommandTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.home = self.root / "home"
        self.repo = self.home / "ghq/github.com/riii111/test"
        self.remote = self.root / "remote.git"
        self.outside = self.root / "outside.txt"
        self.skill = self.home / ".codex/skills/demo"
        self.plugin = self.home / ".codex/plugins/cache/openai-bundled/demo"
        self.plugin_skill = self.plugin / "1.0.0/skills"
        for path in (self.repo, self.skill, self.plugin_skill):
            path.mkdir(parents=True)
        subprocess.run(
            ["git", "init", "-q", "--bare", str(self.remote)],
            check=True,
            capture_output=True,
        )
        git(self.repo, "init", "-q")
        git(self.repo, "config", "user.email", "test@example.com")
        git(self.repo, "config", "user.name", "test")
        git(self.repo, "remote", "add", "origin", "https://github.com/riii111/test.git")
        (self.repo / "file.txt").write_text("one\ntwo\nthree\n")
        (self.skill / "SKILL.md").write_text("skill one\nskill two\n")
        (self.plugin_skill / "SKILL.md").write_text(
            "plugin skill one\nplugin skill two\n"
        )
        (self.plugin / "SKILL.md").write_text("plugin level\n")
        self.outside.write_text("outside\n")
        git(self.repo, "add", "file.txt")
        git(self.repo, "commit", "-q", "-m", "initial")
        git(self.repo, "branch", "-M", "main")
        git(self.repo, "switch", "-q", "-c", "feat/test")

    def run_wrapper(self, wrapper, *args, cwd=None, env=None):
        return subprocess.run(
            [sys.executable, str(wrapper), *map(str, args)],
            cwd=cwd or self.repo,
            env={**os.environ, "HOME": str(self.home), **(env or {})},
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_output(self, result, expected):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected)

    def assert_refused(self, result, message):
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)

    def test_read_lines_reads_approved_roots(self):
        self.assert_output(
            self.run_wrapper(READ_LINES, 2, 3, "file.txt"), "two\nthree\n"
        )
        self.assert_output(
            self.run_wrapper(READ_LINES, 1, 1, "../test/file.txt"), "one\n"
        )
        self.assert_output(
            self.run_wrapper(
                READ_LINES,
                1,
                1,
                "file.txt",
                env={
                    "GIT_DIR": str(self.remote),
                    "GIT_CONFIG_COUNT": "1",
                    "GIT_CONFIG_KEY_0": "remote.origin.url",
                    "GIT_CONFIG_VALUE_0": "https://example.com/riii111/test.git",
                },
            ),
            "one\n",
        )
        self.assert_output(
            self.run_wrapper(READ_LINES, 1, 2, self.skill / "SKILL.md", cwd=self.home),
            "skill one\nskill two\n",
        )
        self.assert_output(
            self.run_wrapper(READ_LINES, 1, 2, self.plugin_skill / "SKILL.md"),
            "plugin skill one\nplugin skill two\n",
        )

    def test_read_lines_rejects_paths_outside_roots(self):
        (self.repo / "escape.txt").symlink_to(self.outside)
        (self.plugin_skill / "escape.txt").symlink_to(self.outside)
        (self.home / ".codex/outside.txt").write_text("outside\n")
        sibling_skill = self.home / ".codex/skills-sibling/SKILL.md"
        sibling_repo = self.repo.with_name("test-sibling") / "file.txt"
        for path in (sibling_skill, sibling_repo):
            path.parent.mkdir(parents=True)
            path.write_text("sibling\n")

        for path in (
            self.plugin / "SKILL.md",
            self.outside,
            "escape.txt",
            self.plugin_skill / "escape.txt",
            sibling_skill,
            sibling_repo,
        ):
            with self.subTest(path=path):
                self.assert_refused(
                    self.run_wrapper(READ_LINES, 1, 1, path), OUTSIDE_ROOT
                )
        self.assert_refused(
            self.run_wrapper(
                READ_LINES,
                1,
                1,
                self.home / ".codex/skills/../outside.txt",
                cwd=self.home,
            ),
            OUTSIDE_ROOT,
        )

    def test_read_lines_rejects_invalid_ranges(self):
        for start, end in ((0, 1), (2, 1)):
            with self.subTest(start=start, end=end):
                self.assert_refused(
                    self.run_wrapper(READ_LINES, start, end, "file.txt"),
                    "invalid line range",
                )

    def test_wrappers_reject_untrusted_remotes(self):
        ssh = self.home / ".ssh"
        ssh.mkdir()
        (ssh / "config").write_text("Host work-github\n  HostName github.com\n")
        url = "https://github.com/riii111/test.git"

        git(
            self.repo,
            "remote",
            "set-url",
            "origin",
            "https://work-github/riii111/test.git",
        )
        self.assert_refused(
            self.run_wrapper(READ_LINES, 2, 3, "file.txt"), OUTSIDE_ROOT
        )
        git(self.repo, "remote", "set-url", "origin", url)

        rewrite = f"url.file://{self.remote}"
        git(self.repo, "config", f"{rewrite}.insteadOf", url)
        self.assert_refused(
            self.run_wrapper(READ_LINES, 2, 3, "file.txt"), OUTSIDE_ROOT
        )
        git(self.repo, "config", "--unset-all", f"{rewrite}.insteadOf")

        git(self.repo, "config", f"{rewrite}.pushInsteadOf", url)
        self.assert_refused(
            self.run_wrapper(READ_LINES, 2, 3, "file.txt"), OUTSIDE_ROOT
        )
        self.assert_refused(self.run_wrapper(FORCE_WITH_LEASE), UNTRUSTED_CHECKOUT)
        git(self.repo, "config", "--unset-all", f"{rewrite}.pushInsteadOf")

        for setting in ("remote.origin.url", "remote.origin.pushurl"):
            with self.subTest(setting=setting):
                git(self.repo, "config", "--add", setting, url)
                git(
                    self.repo,
                    "config",
                    "--add",
                    setting,
                    "https://github.com/riii111/other.git",
                )
                self.assert_refused(
                    self.run_wrapper(READ_LINES, 2, 3, "file.txt"), OUTSIDE_ROOT
                )
                self.assert_refused(
                    self.run_wrapper(FORCE_WITH_LEASE), UNTRUSTED_CHECKOUT
                )
                git(self.repo, "config", "--unset-all", setting)
                git(self.repo, "remote", "set-url", "origin", url)

        git(
            self.repo,
            "remote",
            "set-url",
            "origin",
            "https://example.com/riii111/test.git",
        )
        self.assert_refused(self.run_wrapper(FORCE_WITH_LEASE), UNTRUSTED_CHECKOUT)

    def test_installed_wrappers_work_from_linked_worktree(self):
        worktree = self.root / "worktree"
        git(self.repo, "worktree", "add", "-q", str(worktree), "main")
        (worktree / "worktree.txt").write_text("worktree only\n")
        installed = self.home / "bin"
        shutil.copytree(ROOT / "bin/lib/dot", installed / "lib/dot")
        shutil.copy(READ_LINES, installed / "codex-read-lines")
        shutil.copy(FORCE_WITH_LEASE, installed / "codex-force-with-lease")

        for wrapper in (READ_LINES, installed / "codex-read-lines"):
            with self.subTest(wrapper=wrapper):
                self.assert_output(
                    self.run_wrapper(wrapper, 1, 1, "worktree.txt", cwd=worktree),
                    "worktree only\n",
                )
        for wrapper in (FORCE_WITH_LEASE, installed / "codex-force-with-lease"):
            with self.subTest(wrapper=wrapper):
                self.assert_refused(
                    self.run_wrapper(wrapper, cwd=worktree),
                    "force-with-lease requires a non-protected branch",
                )

    def test_force_with_lease_rejects_arguments(self):
        self.assert_refused(
            self.run_wrapper(FORCE_WITH_LEASE, "unexpected"),
            "usage: codex-force-with-lease",
        )
