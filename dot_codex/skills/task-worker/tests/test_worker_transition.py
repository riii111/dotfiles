import importlib.util
import json
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
                    review=self.review("pending", head_sha=None, turn_id="review-turn")
                ),
                "wait_review",
            ),
            (
                self.state(review=self.review(non_blocking=1)),
                "address_review",
            ),
            (
                self.state(
                    head_sha="head-2",
                    review=self.review(non_blocking=1, applied_head_sha="head-2"),
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
                    review=self.review("pending", head_sha=None, turn_id="review-turn"),
                )
            )
        with self.assertRaisesRegex(transition.TransitionError, "absent review"):
            transition.next_action(
                self.state(
                    pr="absent",
                    head_sha=None,
                    review=self.review(
                        "absent",
                        head_sha="old-head",
                        thread_id=None,
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
        state = self.state(review=self.review(blocking=1, applied_head_sha="head-1"))
        self.assertEqual(transition.next_action(state), "request_review")

    def test_rejects_stale_review_and_checks(self):
        with self.assertRaisesRegex(transition.TransitionError, "reviewed head"):
            transition.next_action(
                self.state(
                    head_sha="head-2",
                    review=self.review(),
                )
            )
        with self.assertRaisesRegex(transition.TransitionError, "checks state"):
            transition.next_action(
                self.state(
                    review=self.review(),
                    checks=self.checks("pending", "old-head"),
                )
            )
        with self.assertRaisesRegex(transition.TransitionError, "checks state"):
            transition.reduce_state(
                self.state(
                    review=self.review(),
                    checks=self.checks("pending"),
                    head_sha="head-2",
                ),
                {
                    "type": "checks_completed",
                    "head_sha": "head-1",
                    "status": "failed",
                },
            )
        with self.assertRaisesRegex(transition.TransitionError, "checks state"):
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
        with self.assertRaisesRegex(transition.TransitionError, "unmerged"):
            transition.reduce_state(
                self.state(completion_note_saved=True), {"type": "merged"}
            )

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

    def test_events_reject_skipped_and_incomplete_transitions(self):
        with self.assertRaisesRegex(transition.TransitionError, "invalid"):
            transition.reduce_state(
                transition.initial_state("manual"), {"type": "merged"}
            )
        with self.assertRaisesRegex(
            transition.TransitionError, "missing or unknown fields"
        ):
            transition.reduce_state(
                self.state(),
                {
                    "type": "review_requested",
                    "thread_id": "review-thread",
                },
            )
        with self.assertRaisesRegex(transition.TransitionError, "no head SHA"):
            transition.reduce_state(self.state(head_sha=None), {"type": "merged"})

    def test_manual_external_merge_syncs_existing_completion_note(self):
        state = self.state(
            review=self.review(),
            checks=self.checks(),
        )
        self.assertEqual(transition.next_action(state), "report_manual")

        state = transition.reduce_state(state, {"type": "merged"})
        self.assertEqual(transition.next_action(state), "record_completion_note")

        state = transition.reduce_state(state, {"type": "completion_note_saved"})
        self.assertEqual(transition.next_action(state), "complete")

    def test_external_merge_and_close_are_terminal_from_active_processing(self):
        pending = self.state(
            review=self.review("pending", head_sha=None, turn_id="review-turn")
        )
        merged = transition.reduce_state(pending, {"type": "merged"})
        closed = transition.reduce_state(pending, {"type": "closed"})

        self.assertEqual(transition.next_action(merged), "record_completion_note")
        self.assertEqual(transition.next_action(closed), "stop_closed")
        with self.assertRaisesRegex(transition.TransitionError, "invalid"):
            transition.reduce_state(merged, {"type": "closed"})

    def test_verify_accepts_already_completed_checks(self):
        state = self.state(review=self.review())
        completed = transition.reduce_state(
            state,
            {"type": "checks_completed", "head_sha": "head-1", "status": "passed"},
        )

        self.assertEqual(transition.next_action(completed), "report_manual")

    def test_review_findings_cannot_come_from_a_stale_head(self):
        with self.assertRaisesRegex(transition.TransitionError, "reviewed head"):
            transition.next_action(
                self.state(
                    head_sha="head-2",
                    review=self.review(non_blocking=1),
                )
            )

    def test_worker_generation_gets_a_distinct_state_path(self):
        first = transition.worker_state_path("example", "T5", "thread-one")
        second = transition.worker_state_path("example", "T5", "thread-two")

        self.assertNotEqual(first, second)

    def test_displayed_event_schemas_match_accepted_events(self):
        samples = {
            "pr_created": {"type": "pr_created", "head_sha": "head-1"},
            "review_requested": {
                "type": "review_requested",
                "thread_id": "review-thread",
                "turn_id": "review-turn",
            },
            "review_completed": {
                "type": "review_completed",
                "head_sha": "head-1",
                "blocking": 0,
                "non_blocking": 0,
            },
            "changes_applied": {"type": "changes_applied", "head_sha": "head-1"},
            "checks_started": {"type": "checks_started", "head_sha": "head-1"},
            "checks_completed": {
                "type": "checks_completed",
                "head_sha": "head-1",
                "status": "passed",
            },
            "marked_ready": {"type": "marked_ready"},
            "mergeability_changed": {
                "type": "mergeability_changed",
                "mergeable": True,
            },
            "merged": {"type": "merged"},
            "closed": {"type": "closed"},
            "completion_note_saved": {"type": "completion_note_saved"},
        }
        states = [
            transition.initial_state("manual"),
            self.state(),
            self.state(
                review=self.review("pending", head_sha=None, turn_id="review-turn")
            ),
            self.state(review=self.review()),
            self.state(review=self.review(), checks=self.checks()),
            self.state(
                pr="ready",
                review=self.review(),
                checks=self.checks(),
                policy="auto",
            ),
            self.state(pr="merged"),
        ]

        for state in states:
            displayed = transition.allowed_event_schemas(state)
            self.assertEqual(set(displayed), set(transition.allowed_events(state)))
            for event_type, fields in displayed.items():
                self.assertEqual(set(fields), transition.EVENT_FIELDS[event_type])
                transition.reduce_state(state, samples[event_type])
            for event_type in set(samples) - set(displayed):
                with self.assertRaises(transition.TransitionError):
                    transition.reduce_state(state, samples[event_type])

    def test_unmergeable_pull_request_cannot_merge(self):
        for pr in ("draft", "ready"):
            self.assertEqual(
                transition.next_action(
                    self.state(
                        pr=pr,
                        review=self.review(),
                        checks=self.checks(),
                        policy="auto",
                        mergeable=False,
                    )
                ),
                "stop_conflict",
            )


if __name__ == "__main__":
    unittest.main()
