import importlib.machinery
import importlib.util
import io
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
READ_LINES = ROOT / "bin" / "executable_codex-read-lines"


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


class ForceWithLeaseTest(unittest.TestCase):
    def run_main(self, run_git):
        module = load_wrapper()
        with (
            mock.patch.object(
                module.git_trust, "trusted_repository", return_value=ROOT
            ),
            mock.patch.object(module.git_trust, "run_git", side_effect=run_git),
            mock.patch.object(sys, "argv", ["codex-force-with-lease"]),
            redirect_stderr(io.StringIO()),
        ):
            return module.main()

    def test_protected_branch_is_not_pushed(self):
        calls = []

        def fake_run_git(cwd, *args):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, stdout="main\n", stderr="")

        self.assertEqual(self.run_main(fake_run_git), 1)
        self.assertFalse(any(args[0] == "push" for args in calls))

    def test_missing_remote_branch_is_not_created(self):
        calls = []

        def fake_run_git(cwd, *args):
            calls.append(args)
            stdout = "feat/test\n" if args[0] == "symbolic-ref" else ""
            return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")

        self.assertEqual(self.run_main(fake_run_git), 1)
        self.assertFalse(any(args[0] == "push" for args in calls))

    def test_push_is_leased_on_the_remote_oid(self):
        calls = []
        old_oid = "1" * 40
        local_oid = "2" * 40

        def fake_run_git(cwd, *args):
            calls.append(args)
            if args[0] == "symbolic-ref":
                stdout = "feat/test\n"
            elif args[0] == "ls-remote":
                stdout = f"{old_oid}\trefs/heads/feat/test\n"
            elif args[0] == "rev-parse":
                stdout = f"{local_oid}\n"
            else:
                stdout = ""
            return subprocess.CompletedProcess(args, 0, stdout=stdout, stderr="")

        self.run_main(fake_run_git)

        push = next(args for args in calls if args[0] == "push")
        self.assertIn(f"--force-with-lease=refs/heads/feat/test:{old_oid}", push)
        self.assertIn(f"{local_oid}:refs/heads/feat/test", push)


def git(cwd, *args):
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True)


class ReadLinesTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.home = self.root / "home"
        self.repo = self.home / "ghq/github.com/riii111/test"
        self.outside = self.root / "outside.txt"
        self.plugin = self.home / ".codex/plugins/cache/openai-bundled/demo"
        self.plugin_skill = self.plugin / "1.0.0/skills"
        for path in (self.repo, self.plugin_skill):
            path.mkdir(parents=True)
        git(self.repo, "init", "-q")
        git(self.repo, "remote", "add", "origin", "https://github.com/riii111/test.git")
        (self.repo / "file.txt").write_text("one\n")
        (self.plugin_skill / "SKILL.md").write_text("plugin skill\n")
        (self.plugin / "SKILL.md").write_text("plugin level\n")
        self.outside.write_text("outside\n")

    def read(self, path, cwd=None, env=None):
        return subprocess.run(
            [sys.executable, str(READ_LINES), "1", "1", str(path)],
            cwd=cwd or self.repo,
            env={**os.environ, "HOME": str(self.home), **(env or {})},
            capture_output=True,
            text=True,
            check=False,
        )

    def assert_read(self, path, expected, env=None):
        result = self.read(path, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected)

    def assert_refused(self, path, cwd=None):
        result = self.read(path, cwd)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_reads_approved_roots(self):
        self.assert_read("file.txt", "one\n")
        # Git settings from the environment cannot redirect the trust check.
        self.assert_read(
            "file.txt",
            "one\n",
            env={
                "GIT_DIR": str(self.outside.parent),
                "GIT_CONFIG_COUNT": "1",
                "GIT_CONFIG_KEY_0": "remote.origin.url",
                "GIT_CONFIG_VALUE_0": "https://example.com/riii111/test.git",
            },
        )
        self.assert_read(self.plugin_skill / "SKILL.md", "plugin skill\n")

    def test_rejects_paths_outside_roots(self):
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
                self.assert_refused(path)
        self.assert_refused(self.home / ".codex/skills/../outside.txt", cwd=self.home)

    def reset_origin(self):
        subprocess.run(
            ["git", "-C", str(self.repo), "remote", "remove", "origin"],
            capture_output=True,
        )
        subprocess.run(
            ["git", "-C", str(self.repo), "config", "--remove-section", self.rewrite],
            capture_output=True,
        )
        git(self.repo, "remote", "add", "origin", self.url)

    def test_rejects_untrusted_remotes(self):
        self.url = "https://github.com/riii111/test.git"
        self.rewrite = f"url.file://{self.root / 'remote.git'}"
        for config in (
            ["remote", "set-url", "origin", "https://work-github/riii111/test.git"],
            ["remote", "set-url", "origin", "https://example.com/riii111/test.git"],
            ["config", f"{self.rewrite}.insteadOf", self.url],
            ["config", f"{self.rewrite}.pushInsteadOf", self.url],
            ["config", "--add", "remote.origin.url", "https://github.com/a/b.git"],
            ["config", "--add", "remote.origin.pushurl", "https://github.com/a/b.git"],
        ):
            with self.subTest(config=config):
                self.reset_origin()
                git(self.repo, *config)
                self.assert_refused("file.txt")
                with mock.patch.dict(os.environ, {"HOME": str(self.home)}):
                    self.assertIsNone(git_trust.trusted_repository(self.repo))
