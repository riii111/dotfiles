import importlib.machinery
import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_hook():
    path = ROOT / "dot_codex/hooks/executable_permission_request.py"
    loader = importlib.machinery.SourceFileLoader("permission_request_hook", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GitHubHostTest(unittest.TestCase):
    def test_ssh_config_timeout_is_untrusted(self):
        module = load_hook()
        with mock.patch.object(
            module.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired(["ssh", "-G"], 2),
        ):
            self.assertIs(module.github_host("github.com"), False)
