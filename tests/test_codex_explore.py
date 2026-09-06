import json
import tempfile
import unittest
from pathlib import Path

from bin.lib.codex_explore import (
    DEFAULT_ASTRA_MODEL,
    DEFAULT_SOL_MODEL,
    JsonlLogger,
    RunOptions,
    RouterSession,
)


class FakeClient:
    def __init__(self):
        self.sent = []
        self.next_id = 1
        self.stderr_lines = []

    def send(self, method, params=None):
        request_id = self.next_id
        self.next_id += 1
        self.sent.append((request_id, method, params))
        return request_id


def make_session(tmpdir, mode="auto", explore=True):
    logger = JsonlLogger(Path(tmpdir) / "events.jsonl", "test-run")
    logger.__enter__()
    options = RunOptions(
        prompt="inspect the repository",
        cwd=Path(tmpdir),
        mode=mode,
        explore=explore,
        skill_path=Path(tmpdir) / "SKILL.md",
        threshold_seconds=1,
    )
    session = RouterSession(options, logger)
    session.client = FakeClient()
    session.state.thread_id = "thread-1"
    session.state.active_turn_id = "turn-1"
    session.state.current_model = DEFAULT_SOL_MODEL
    session.state.start_model = DEFAULT_SOL_MODEL
    session.state.turn_started_monotonic = 0
    return session, logger


class ExploreRouterStateTest(unittest.TestCase):
    def test_natural_completion_does_not_start_astra(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_turn_completed({"id": "turn-1", "status": "completed"})
            self.assertEqual(session.state.final_status, "completed")
            self.assertFalse(
                any(method == "turn/start" for _, method, _ in session.client.sent)
            )
            logger.__exit__()

    def test_final_answer_completion_waits_for_turn_completion(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_notification(
                "item/agentMessage/delta",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "itemId": "answer",
                    "delta": "final",
                },
            )
            session.handle_notification(
                "item/completed",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "item": {
                        "id": "answer",
                        "type": "agentMessage",
                        "phase": "final_answer",
                    },
                },
            )
            self.assertEqual(session.client.sent, [])
            session.handle_turn_completed({"id": "turn-1", "status": "completed"})
            self.assertEqual(session.state.final_status, "completed")
            self.assertTrue(session.state.natural_completion)
            logger.__exit__()

    def test_user_cancellation_does_not_restart(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.state.user_cancelled = True
            session.maybe_request_switch(2)
            self.assertEqual(session.client.sent, [])
            logger.__exit__()

    def test_interrupt_is_requested_once(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.maybe_request_switch(2)
            session.maybe_request_switch(3)
            self.assertEqual(
                [method for _, method, _ in session.client.sent], ["turn/interrupt"]
            )
            self.assertEqual(session.state.switch_count, 1)
            logger.__exit__()

    def test_observe_records_threshold_without_interrupting(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir, mode="observe")
            session.maybe_request_switch(2)
            self.assertTrue(session.state.condition_met)
            self.assertEqual(session.state.switch_state, "condition_observed")
            self.assertEqual(session.client.sent, [])
            logger.__exit__()

    def test_switch_requires_explore_root_started_with_sol(self):
        cases = (
            {"explore": False},
            {"parent_thread_id": "parent-thread"},
            {"start_model": DEFAULT_ASTRA_MODEL, "current_model": DEFAULT_ASTRA_MODEL},
        )
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmpdir:
                session, logger = make_session(
                    tmpdir, explore=case.get("explore", True)
                )
                for name, value in case.items():
                    setattr(session.state, name, value)
                session.maybe_request_switch(2)
                self.assertEqual(session.client.sent, [])
                logger.__exit__()

    def test_pending_tool_defers_interrupt_until_item_completes(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_notification(
                "item/started",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "item": {"id": "command-1", "type": "commandExecution"},
                },
            )
            session.maybe_request_switch(2)
            self.assertEqual(session.client.sent, [])
            session.handle_notification(
                "item/completed",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "item": {"id": "command-1", "type": "commandExecution"},
                },
            )
            self.assertEqual(
                [method for _, method, _ in session.client.sent], ["turn/interrupt"]
            )
            logger.__exit__()

    def test_interrupt_response_does_not_start_astra_until_completion(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.maybe_request_switch(2)
            session.handle_response("turn/interrupt", {"result": {}})
            self.assertFalse(
                any(method == "turn/start" for _, method, _ in session.client.sent)
            )
            session.handle_turn_completed({"id": "turn-1", "status": "interrupted"})
            starts = [
                params
                for _, method, params in session.client.sent
                if method == "turn/start"
            ]
            self.assertEqual(len(starts), 1)
            self.assertEqual(starts[0]["model"], DEFAULT_ASTRA_MODEL)
            self.assertEqual(starts[0]["effort"], "low")
            logger.__exit__()

    def test_astra_turn_starts_only_once_after_completion_event(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.maybe_request_switch(2)
            session.handle_turn_completed({"id": "turn-1", "status": "interrupted"})
            session.handle_turn_completed({"id": "turn-1", "status": "interrupted"})
            self.assertEqual(
                sum(method == "turn/start" for _, method, _ in session.client.sent), 1
            )
            session.handle_response(
                "turn/start",
                {"result": {"turn": {"id": "turn-2", "status": "inProgress"}}},
            )
            self.assertTrue(session.state.astra_started)
            self.assertEqual(session.state.active_turn_id, "turn-2")
            logger.__exit__()

    def test_other_thread_and_turn_events_are_ignored(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_notification(
                "item/agentMessage/delta",
                {
                    "threadId": "child-thread",
                    "turnId": "turn-1",
                    "itemId": "child-answer",
                    "delta": "child",
                },
            )
            session.handle_notification(
                "item/agentMessage/delta",
                {
                    "threadId": "thread-1",
                    "turnId": "old-turn",
                    "itemId": "old-answer",
                    "delta": "old",
                },
            )
            self.assertEqual(session.state.agent_messages, {})
            logger.__exit__()

    def test_messages_keep_insertion_order_and_final_phase(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            for item_id, text in (("progress", "progress"), ("answer", "final")):
                session.handle_notification(
                    "item/agentMessage/delta",
                    {
                        "threadId": "thread-1",
                        "turnId": "turn-1",
                        "itemId": item_id,
                        "delta": text,
                    },
                )
            session.handle_notification(
                "item/completed",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "item": {
                        "id": "progress",
                        "type": "agentMessage",
                        "phase": "commentary",
                    },
                },
            )
            session.handle_notification(
                "item/completed",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "item": {
                        "id": "answer",
                        "type": "agentMessage",
                        "phase": "final_answer",
                    },
                },
            )
            session.handle_turn_completed({"id": "turn-1", "status": "completed"})
            self.assertEqual(list(session.state.agent_messages), ["progress", "answer"])
            self.assertEqual(session.final_answer(), "final")
            logger.__exit__()

    def test_missing_usage_is_unknown_and_snapshots_are_not_summed(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            usage = {"total": {"totalTokens": 10}}
            session.handle_notification(
                "thread/tokenUsage/updated",
                {"threadId": "thread-1", "turnId": "turn-1", "tokenUsage": usage},
            )
            session.handle_notification(
                "thread/tokenUsage/updated",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "tokenUsage": {"total": {"totalTokens": 20}},
                },
            )
            self.assertEqual(
                session.state.usage_by_thread["thread-1"]["token_usage"]["total"][
                    "totalTokens"
                ],
                20,
            )
            self.assertIsNone(session.estimated_credits())
            self.assertEqual(session.measurement_completeness(), "partial")
            logger.__exit__()

    def test_child_token_gap_is_partial_and_completion_log_keeps_measurements(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.state.completed_monotonic = session.state.started_monotonic + 1
            session.state.final_status = "completed"
            session.state.usage_by_thread = {
                "thread-1": {
                    "token_usage": {"total": {"totalTokens": 20}},
                    "account_usage": {
                        "threadUsage": {"estimatedUsageCreditsMicros": 100}
                    },
                },
                "child-thread": {
                    "account_usage": {
                        "threadUsage": {"estimatedUsageCreditsMicros": 50}
                    }
                },
            }
            self.assertEqual(session.measurement_completeness(), "partial")
            self.assertAlmostEqual(session.estimated_credits(), 0.00015)
            session.state.usage_by_thread["child-thread"]["token_usage"] = {
                "total": {"totalTokens": 7}
            }
            result = session.result()
            self.assertAlmostEqual(result["estimated_usage_credits"], 0.00015)
            records = [
                json.loads(line)
                for line in (Path(tmpdir) / "events.jsonl").read_text().splitlines()
            ]
            completed = next(
                record for record in records if record["event"] == "run_completed"
            )
            self.assertEqual(completed["token_usage"]["total"]["totalTokens"], 20)
            self.assertAlmostEqual(completed["estimated_usage_credits"], 0.00015)
            logger.__exit__()


if __name__ == "__main__":
    unittest.main()
