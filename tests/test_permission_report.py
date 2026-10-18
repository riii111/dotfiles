import importlib.machinery
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


class LogPermissionEventTest(unittest.TestCase):
    def setUp(self):
        path = ROOT / "dot_claude" / "hooks" / "executable_log-permission-event.py"
        loader = importlib.machinery.SourceFileLoader("log_permission_event", str(path))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        assert spec is not None and spec.loader is not None
        self.hook = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.hook)

    def run_hook(self, payload, log):
        self.hook.LOG = log
        stdin = io.StringIO(
            payload if isinstance(payload, str) else json.dumps(payload)
        )
        stdout = io.StringIO()
        with mock.patch.object(self.hook.sys, "stdin", stdin), redirect_stdout(stdout):
            self.assertEqual(self.hook.main(), 0)
        return stdout.getvalue()

    def test_records_bash_prompt_without_deciding(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "state" / "events.jsonl"
            output = self.run_hook(
                {
                    "hook_event_name": "PermissionRequest",
                    "session_id": "s1",
                    "cwd": "/repo",
                    "permission_mode": "auto",
                    "tool_name": "Bash",
                    "tool_input": {
                        "command": "x" * 600,
                        "dangerouslyDisableSandbox": True,
                    },
                },
                log,
            )
            record = json.loads(log.read_text())
            mode = log.stat().st_mode & 0o777
        self.assertEqual(output, "")
        self.assertEqual(mode, 0o600)
        self.assertEqual(record["event"], "PermissionRequest")
        self.assertEqual(len(record["command"]), 500)
        self.assertTrue(record["unsandboxed"])

    def test_bad_input_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "events.jsonl"
            self.assertEqual(self.run_hook("not json", log), "")
            self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
