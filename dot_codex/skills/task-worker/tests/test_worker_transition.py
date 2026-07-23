import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SKILL_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "worker_transition", SKILL_ROOT / "scripts" / "worker_transition.py"
)
transition = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(transition)


class WorkerTransitionTest(unittest.TestCase):
    def state(self, **overrides):
        state = {
            "pr": "draft",
            "review": "absent",
            "checks": "not_run",
            "policy": "manual",
            "completion_note_saved": False,
        }
        state.update(overrides)
        return state

    def test_returns_one_action_for_each_lifecycle_stage(self):
        cases = [
            (self.state(pr="absent"), "implement"),
            (self.state(), "request_review"),
            (self.state(review="pending"), "wait_review"),
            (self.state(review="changes_required"), "address_review"),
            (self.state(review="passed"), "verify"),
            (self.state(review="passed", checks="pending"), "wait_checks"),
            (self.state(review="passed", checks="passed"), "report_manual"),
            (
                self.state(
                    review="passed", checks="passed", policy="auto"
                ),
                "mark_ready",
            ),
            (
                self.state(
                    pr="ready",
                    review="passed",
                    checks="passed",
                    policy="auto",
                ),
                "merge",
            ),
            (
                self.state(pr="merged", review="passed", checks="passed"),
                "record_completion_note",
            ),
            (
                self.state(
                    pr="merged",
                    review="passed",
                    checks="passed",
                    completion_note_saved=True,
                ),
                "complete",
            ),
        ]

        for state, expected in cases:
            with self.subTest(expected=expected):
                self.assertEqual(transition.next_action(state), expected)

    def test_failed_verification_is_retried_after_resume(self):
        self.assertEqual(
            transition.next_action(
                self.state(review="passed", checks="failed", policy="auto")
            ),
            "verify",
        )

    def test_rejects_manual_ready_and_premature_completion_note(self):
        with self.assertRaisesRegex(transition.TransitionError, "manual policy"):
            transition.next_action(
                self.state(pr="ready", review="passed", checks="passed")
            )
        with self.assertRaisesRegex(transition.TransitionError, "unmerged"):
            transition.next_action(
                self.state(completion_note_saved=True)
            )

    def test_rejects_merged_state_without_completed_processing(self):
        with self.assertRaisesRegex(transition.TransitionError, "lacks passed"):
            transition.next_action(self.state(pr="merged"))

    def test_cli_rejects_unknown_and_missing_state(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "state.json"
            path.write_text(json.dumps({"pr": "unknown"}))
            result = subprocess.run(
                [sys.executable, str(SPEC.origin), "--state", str(path)],
                capture_output=True,
                check=False,
                text=True,
            )

        self.assertEqual(result.returncode, 2)
        self.assertIn("missing or unknown fields", result.stderr)


if __name__ == "__main__":
    unittest.main()
