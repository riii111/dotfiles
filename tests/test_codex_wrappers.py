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


class ForceWithLeaseTest(unittest.TestCase):
    def test_https_alias_is_not_a_github_host(self):
        for filename in (
            "executable_codex-force-with-lease",
            "executable_codex-read-lines",
        ):
            module = load_wrapper(filename)
            self.assertIsNone(
                module.github_repository("https://work-github/riii111/test.git")
            )
            module.github_host = lambda host: host == "work-github"
            self.assertIsNone(
                module.github_repository("git@github.com:riii111/test.git")
            )
            self.assertEqual(
                module.github_repository("git@work-github:riii111/test.git"),
                ("riii111", "test"),
            )
            self.assertEqual(
                module.github_repository("ssh://work-github/riii111/test.git"),
                ("riii111", "test"),
            )

    def test_ssh_config_timeout_is_untrusted(self):
        modules = [
            load_wrapper("executable_codex-force-with-lease"),
            load_wrapper("executable_codex-read-lines"),
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
                self.assertFalse(module.github_host("github.com"))

    def test_effective_push_url_must_be_trusted(self):
        module = load_wrapper()
        calls = []

        def fake_run_git(cwd, *args):
            calls.append(args)
            if args == ("remote", "get-url", "--all", "origin"):
                return subprocess.CompletedProcess(
                    args, 0, stdout="git@github.com:riii111/test.git\n", stderr=""
                )
            if args == ("remote", "get-url", "--push", "--all", "origin"):
                return subprocess.CompletedProcess(
                    args, 0, stdout="file:///tmp/remote.git\n", stderr=""
                )
            raise AssertionError(args)

        with tempfile.TemporaryDirectory() as directory:
            root = (
                Path(directory) / "ghq" / "github.com" / "riii111" / "test"
            ).resolve()
            with mock.patch.object(module.Path, "home", return_value=Path(directory)):
                module.run_git = fake_run_git
                self.assertFalse(module.trusted_repository(root, root))

        self.assertEqual(
            calls,
            [
                ("remote", "get-url", "--all", "origin"),
                ("remote", "get-url", "--push", "--all", "origin"),
            ],
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
                module.repository_root = lambda cwd: Path(directory)
                module.trusted_repository = lambda cwd, root: True
                module.run_git = fake_run_git
                sys.argv = [str(ROOT / "bin" / "executable_codex-force-with-lease")]
                with redirect_stderr(io.StringIO()):
                    self.assertEqual(module.main(), 1)
            finally:
                os.chdir(original_cwd)

        push = next(args for args in calls if args[:2] == ("push", "origin"))
        self.assertIn(
            f"--force-with-lease=refs/heads/feat/test:{old_oid}",
            push,
        )
        self.assertIn(f"{local_oid}:refs/heads/feat/test", push)

    def test_push_uses_captured_local_branch_oid(self):
        module = load_wrapper()
        calls = []
        remote_oid = "1" * 40
        captured_oid = "2" * 40
        changed_head_oid = "3" * 40

        def fake_run_git(cwd, *args):
            calls.append(args)
            if args[:3] == ("symbolic-ref", "--quiet", "--short"):
                return subprocess.CompletedProcess(
                    args, 0, stdout="feat/test\n", stderr=""
                )
            if args[:3] == ("ls-remote", "--heads", "origin"):
                return subprocess.CompletedProcess(
                    args, 0, stdout=f"{remote_oid}\trefs/heads/feat/test\n", stderr=""
                )
            if args[:3] == ("rev-parse", "--verify", "refs/heads/feat/test"):
                return subprocess.CompletedProcess(
                    args, 0, stdout=f"{captured_oid}\n", stderr=""
                )
            if args[:3] == ("rev-parse", "--verify", "HEAD"):
                return subprocess.CompletedProcess(
                    args, 0, stdout=f"{changed_head_oid}\n", stderr=""
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
                module.repository_root = lambda cwd: Path(directory)
                module.trusted_repository = lambda cwd, root: True
                module.run_git = fake_run_git
                sys.argv = [str(ROOT / "bin" / "executable_codex-force-with-lease")]
                with redirect_stderr(io.StringIO()):
                    self.assertEqual(module.main(), 1)
            finally:
                os.chdir(original_cwd)

        push = next(args for args in calls if args[:2] == ("push", "origin"))
        self.assertIn(f"{captured_oid}:refs/heads/feat/test", push)
        self.assertNotIn(f"{changed_head_oid}:refs/heads/feat/test", push)
