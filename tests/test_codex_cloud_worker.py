from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


HELPER = (
    Path(__file__).resolve().parents[1]
    / "dot_codex/skills/task-orchestration/references/codex-cloud-worker.py"
)
REPO = "sample/repo"
TASK = "TASK-101"
WORKER = "96729258-0d86-4771-9f59-6ee4d981edc5"
OTHER_WORKER = "6bcd2de1-6724-4a0e-9780-c9c7ad5b1eb8"


class CodexCloudWorkerTest(unittest.TestCase):
    def setUp(self):
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        self.root = Path(workspace.name)
        self.state = self.root / "state"

    def call(self, command, *args, task=TASK, success=True):
        result = subprocess.run(
            [sys.executable, str(HELPER), command, REPO, task, *args],
            cwd=self.root,
            env=dict(os.environ, XDG_STATE_HOME=str(self.state)),
            check=success,
            text=True,
            capture_output=True,
        )
        return json.loads(result.stdout) if success else result

    def test_reopened_orchestrator_reuses_attached_worker(self):
        with ThreadPoolExecutor() as pool:
            reservations = list(pool.map(lambda _: self.call("prepare"), range(4)))
        self.assertEqual(sum(item["created"] for item in reservations), 1)
        self.assertEqual(self.call("get"), {"status": "pending"})

        worker = {"status": "attached", "hostId": "durable", "threadId": WORKER}
        self.assertEqual(self.call("attach", WORKER), worker)
        self.assertEqual(self.call("get"), worker)
        self.assertEqual(self.call("prepare"), dict(worker, created=False))
        self.assertNotEqual(
            self.call("attach", OTHER_WORKER, success=False).returncode, 0
        )
        self.assertEqual(self.call("get"), worker)

    def test_cancel_only_releases_pending_reservation(self):
        self.call("prepare")
        self.assertIsNone(self.call("cancel"))
        self.assertTrue(self.call("prepare")["created"])
        self.call("attach", WORKER)
        self.assertNotEqual(self.call("cancel", success=False).returncode, 0)
        self.assertEqual(self.call("get")["threadId"], WORKER)

    def test_unreadable_registry_does_not_look_unregistered(self):
        self.assertIsNone(self.call("get"))
        self.assertFalse(self.state.exists())
        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.object(sys, "argv", [str(HELPER), "get", REPO, TASK]),
            mock.patch.dict(os.environ, XDG_STATE_HOME=str(self.state)),
            mock.patch.object(
                Path, "stat", side_effect=PermissionError("state denied")
            ),
            redirect_stdout(stdout),
            redirect_stderr(stderr),
            self.assertRaises(SystemExit) as failure,
        ):
            runpy.run_path(str(HELPER), run_name="__main__")
        self.assertEqual(failure.exception.code, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertIn("state denied", stderr.getvalue())
