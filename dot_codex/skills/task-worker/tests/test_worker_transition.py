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
            "head_sha": "head-1",
            "mergeable": True,
            "review": {
                "status": "absent",
                "head_sha": None,
                "applied_head_sha": None,
                "blocking": 0,
                "non_blocking": 0,
                "thread_id": None,
                "turn_id": None,
            },
            "checks": {"status": "not_run", "head_sha": None},
            "policy": "manual",
            "completion_note_saved": False,
        }
        state.update(overrides)
        return state

    def review(self, status="completed", **overrides):
        review = {
            "status": status,
            "head_sha": "head-1",
            "applied_head_sha": None,
            "blocking": 0,
            "non_blocking": 0,
            "thread_id": "review-thread",
            "turn_id": None,
        }
        review.update(overrides)
        return review

    def checks(self, status="passed", head_sha="head-1"):
        return {"status": status, "head_sha": head_sha}

    def test_returns_one_action_for_each_lifecycle_stage(self):
        cases = [
            (self.state(pr="absent", head_sha=None), "implement"),
            (self.state(), "request_review"),
            (
                self.state(
                    review=self.review(
                        "pending", head_sha=None, turn_id="review-turn"
                    )
                ),
                "wait_review",
            ),
            (
                self.state(review=self.review(non_blocking=1)),
                "address_review",
            ),
            (
                self.state(
                    review=self.review(
                        non_blocking=1, applied_head_sha="head-1"
                    )
                ),
                "verify",
            ),
            (
                self.state(
                    review=self.review(),
                    checks=self.checks("pending"),
                ),
                "wait_checks",
            ),
            (
                self.state(review=self.review(), checks=self.checks()),
                "report_manual",
            ),
            (
                self.state(
                    review=self.review(),
                    checks=self.checks(),
                    policy="auto",
                ),
                "mark_ready",
            ),
            (
                self.state(
                    pr="ready",
                    review=self.review(),
                    checks=self.checks(),
                    policy="auto",
                ),
                "merge",
            ),
            (
                self.state(pr="merged"),
                "record_completion_note",
            ),
            (
                self.state(pr="merged", completion_note_saved=True),
                "complete",
            ),
        ]
        for state, expected in cases:
            with self.subTest(expected=expected):
                self.assertEqual(transition.next_action(state), expected)

    def test_review_and_ci_can_progress_independently(self):
        state = self.state(
            review=self.review("pending", head_sha=None, turn_id="review-turn"),
            checks=self.checks(),
        )
        self.assertEqual(transition.next_action(state), "wait_review")

    def test_pr_absent_rejects_review_and_checks_state(self):
        with self.assertRaises(transition.TransitionError):
            transition.next_action(
                self.state(
                    pr="absent",
                    head_sha=None,
                    review=self.review(
                        "pending", head_sha=None, turn_id="review-turn"
                    ),
                )
            )
        with self.assertRaisesRegex(transition.TransitionError, "checks state"):
            transition.next_action(
                self.state(
                    pr="absent",
                    head_sha=None,
                    checks=self.checks(),
                )
            )

    def test_large_review_requires_rereview_after_changes(self):
        state = self.state(
            review=self.review(blocking=1, applied_head_sha="head-1")
        )
        self.assertEqual(transition.next_action(state), "request_review")

    def test_rejects_stale_review_and_checks(self):
        with self.assertRaisesRegex(transition.TransitionError, "accepted review"):
            transition.next_action(
                self.state(
                    head_sha="head-2",
                    review=self.review(),
                )
            )
        with self.assertRaisesRegex(transition.TransitionError, "pending checks"):
            transition.next_action(
                self.state(
                    review=self.review(),
                    checks=self.checks("pending", "old-head"),
                )
            )
        with self.assertRaisesRegex(transition.TransitionError, "passed checks"):
            transition.next_action(
                self.state(
                    review=self.review(),
                    checks=self.checks(head_sha="old-head"),
                )
            )

    def test_rejects_manual_ready_and_premature_completion_note(self):
        with self.assertRaisesRegex(transition.TransitionError, "manual policy"):
            transition.next_action(
                self.state(
                    pr="ready",
                    review=self.review(),
                    checks=self.checks(),
                )
            )
        with self.assertRaisesRegex(transition.TransitionError, "unmerged"):
            transition.next_action(self.state(completion_note_saved=True))

    def test_load_rejects_non_string_and_missing_state_without_traceback(self):
        malformed_states = [{"pr": []}, self.state(pr=[])]
        for malformed in malformed_states:
            with self.subTest(malformed=malformed):
                with tempfile.TemporaryDirectory() as directory:
                    path = Path(directory) / "state.json"
                    path.write_text(json.dumps(malformed))
                    with self.assertRaises(transition.TransitionError):
                        transition.load_state(path)

    def test_events_persist_review_identity_and_advance_one_action(self):
        state = transition.initial_state("manual")
        state = transition.reduce_state(
            state, {"type": "pr_created", "head_sha": "head-1"}
        )
        state = transition.reduce_state(
            state,
            {
                "type": "review_requested",
                "thread_id": "review-thread",
                "turn_id": "review-turn",
            },
        )

        self.assertEqual(transition.next_action(state), "wait_review")
        self.assertEqual(state["review"]["thread_id"], "review-thread")
        self.assertEqual(state["review"]["turn_id"], "review-turn")

    def test_unmergeable_pull_request_cannot_merge(self):
        with self.assertRaisesRegex(transition.TransitionError, "not mergeable"):
            transition.next_action(
                self.state(
                    pr="ready",
                    review=self.review(),
                    checks=self.checks(),
                    policy="auto",
                    mergeable=False,
                )
            )


if __name__ == "__main__":
    unittest.main()
