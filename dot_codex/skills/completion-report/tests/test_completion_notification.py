import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SKILL_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "completion_notification",
    SKILL_ROOT / "scripts" / "completion_notification.py",
)
notification = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(notification)


class CompletionNotificationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.environment = patch.dict(
            os.environ, {"XDG_STATE_HOME": self.temporary.name}
        )
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def test_builds_the_only_allowed_parent_payload(self):
        payload = notification.build_notification(
            "completion-note",
            "TASK-1",
            "Owner/Repository",
            42,
            "ABCDEF0123456789ABCDEF0123456789ABCDEF01",
        )

        self.assertEqual(
            payload,
            {
                "orchestration_id": "completion-note",
                "task_id": "TASK-1",
                "pull_request": {
                    "repository": "owner/repository",
                    "number": 42,
                },
                "merge_commit": "abcdef0123456789abcdef0123456789abcdef01",
                "saved": True,
            },
        )
        self.assertFalse(
            {"risks", "handoff", "review_learnings", "technical_debt"} & payload.keys()
        )

    def test_cli_emits_one_compact_json_object(self):
        common = [
            "completion-note",
            "--task-id",
            "TASK-1",
            "--worker-id",
            "worker-1",
        ]
        prepared = subprocess.run(
            [
                sys.executable,
                str(SPEC.origin),
                "prepare",
                *common,
                "--repository",
                "owner/repository",
                "--number",
                "42",
                "--merge-commit",
                "abcdef0123456789abcdef0123456789abcdef01",
            ],
            capture_output=True,
            check=False,
            text=True,
        )
        result = subprocess.run(
            [sys.executable, str(SPEC.origin), "payload", *common],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(prepared.returncode, 0)
        self.assertEqual(json.loads(prepared.stdout)["status"], "pending")
        self.assertEqual(result.returncode, 0)
        self.assertIs(json.loads(result.stdout)["saved"], True)
        self.assertEqual(result.stdout.count("\n"), 1)
        self.assertNotIn("handoff", result.stdout)

    def test_outbox_retries_pending_and_records_one_submission(self):
        payload = notification.build_notification(
            "completion-note",
            "TASK-1",
            "owner/repository",
            42,
            "a" * 40,
        )
        path = notification.outbox_path("completion-note", "TASK-1", "worker-1")

        first = notification.prepare(path, payload)
        retry = notification.prepare(path, payload)
        submitted = notification.mark_submitted(path, "submission-1")
        repeated = notification.prepare(path, payload)
        idempotent = notification.mark_submitted(path, "submission-1")

        self.assertEqual(first["status"], "pending")
        self.assertEqual(retry["status"], "pending")
        self.assertEqual(submitted["status"], "submitted")
        self.assertEqual(repeated["submission_id"], "submission-1")
        self.assertEqual(idempotent, repeated)
        with self.assertRaisesRegex(
            notification.NotificationError, "another submission"
        ):
            notification.mark_submitted(path, "submission-2")

    def test_outbox_rejects_a_different_notification(self):
        path = notification.outbox_path("completion-note", "TASK-1", "worker-1")
        first = notification.build_notification(
            "completion-note",
            "TASK-1",
            "owner/repository",
            42,
            "a" * 40,
        )
        changed = notification.build_notification(
            "completion-note",
            "TASK-1",
            "owner/repository",
            42,
            "b" * 40,
        )

        notification.prepare(path, first)

        with self.assertRaisesRegex(
            notification.NotificationError, "different notification"
        ):
            notification.prepare(path, changed)

    def test_rejects_untrusted_identifiers_and_merge_evidence(self):
        cases = [
            ("../completion-note", "TASK-1", "owner/repository", 42, "a" * 40),
            ("completion-note", "../TASK-1", "owner/repository", 42, "a" * 40),
            ("completion-note", "TASK-1", "repository", 42, "a" * 40),
            ("completion-note", "TASK-1", "owner/repository", 0, "a" * 40),
            ("completion-note", "TASK-1", "owner/repository", 42, "not-a-sha"),
        ]

        for arguments in cases:
            with self.subTest(arguments=arguments):
                with self.assertRaises(notification.NotificationError):
                    notification.build_notification(*arguments)

    def test_skill_requires_accepted_submission_and_retries_failures(self):
        skill = (SKILL_ROOT / "SKILL.md").read_text()

        self.assertIn("`complete`ならNote処理を繰り返さず手順7", skill)
        self.assertIn("空でない`submission_id`", skill)
        self.assertIn("親が処理中でもsubmissionが受理されれば成功", skill)
        self.assertIn("outboxを`pending`のまま残し", skill)
        self.assertIn("通知未完了", skill)
        self.assertIn("pendingの同じJSONを再送", skill)

    def test_parent_skill_replans_duplicate_notifications_from_current_state(self):
        parent_skill = (
            SKILL_ROOT.parent / "task-orchestration" / "SKILL.md"
        ).read_text()

        self.assertIn("validate-completion-notification", parent_skill)
        self.assertIn("最新task sourceを再読", parent_skill)
        self.assertIn("同じ通知が複数届いても", parent_skill)
        self.assertIn("過去の`plan`結果の再利用は行わない", parent_skill)


if __name__ == "__main__":
    unittest.main()
