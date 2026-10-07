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
