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


def load_wrapper():
    path = ROOT / "bin" / "executable_codex-force-with-lease"
    loader = importlib.machinery.SourceFileLoader("codex_force_with_lease", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class ForceWithLeaseTest(unittest.TestCase):
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
            root = (Path(directory) / "ghq" / "github.com" / "riii111" / "test").resolve()
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

        def fake_run_git(cwd, *args):
            calls.append(args)
            if args[:3] == ("symbolic-ref", "--quiet", "--short"):
                return subprocess.CompletedProcess(args, 0, stdout="feat/test\n", stderr="")
            if args[:3] == ("ls-remote", "--heads", "origin"):
                return subprocess.CompletedProcess(
                    args, 0, stdout=f"{old_oid}\trefs/heads/feat/test\n", stderr=""
                )
            if args[:3] == ("rev-parse", "--verify", "HEAD"):
                return subprocess.CompletedProcess(args, 0, stdout=f"{'2' * 40}\n", stderr="")
            if args[:2] == ("push", "origin"):
                return subprocess.CompletedProcess(args, 1, stdout="", stderr="stale lease\n")
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
        self.assertIn("HEAD:refs/heads/feat/test", push)
