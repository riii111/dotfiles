import json
import tempfile
import time
import unittest
from pathlib import Path

from bin.lib.codex_explore import (
    DEFAULT_ASTRA_MODEL,
    DEFAULT_SOL_MODEL,
    JsonlLogger,
    RunOptions,
    RouterSession,
    TurnExecution,
    TurnResult,
)


class FakeClient:
    def __init__(self):
        self.sent = []
        self.next_id = 1
        self.stderr_lines = []
        self.read_queue = []

    def send(self, method, params=None):
        request_id = self.next_id
        self.next_id += 1
        self.sent.append((request_id, method, params))
        return request_id

    def read(self, _timeout):
        return self.read_queue.pop(0) if self.read_queue else None


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
    session.record.thread_id = "thread-1"
    session.record.start_model = DEFAULT_SOL_MODEL
    session.usage_by_thread("thread-1")
    session.active_turn = TurnExecution(
        model=DEFAULT_SOL_MODEL,
        allow_switch=True,
        turn_id="turn-1",
        started_monotonic=0,
    )
    return session, logger


class ExploreRouterStateTest(unittest.TestCase):
    def test_natural_completion_does_not_start_astra(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_notification(
                "turn/completed",
                {
                    "threadId": "thread-1",
                    "turn": {"id": "turn-1", "status": "completed"},
                },
            )
            result = session.finish_turn(session.active_turn)
            self.assertEqual(result.status, "completed")
            self.assertFalse(result.switch)
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
            session.handle_notification(
                "turn/completed",
                {
                    "threadId": "thread-1",
                    "turn": {"id": "turn-1", "status": "completed"},
                },
            )
            self.assertEqual(
                session.finish_turn(session.active_turn).status, "completed"
            )
            logger.__exit__()

    def test_user_cancellation_does_not_restart(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.record.user_cancelled = True
            self.assertFalse(session.maybe_request_switch(session.active_turn, 2))
            self.assertEqual(session.client.sent, [])
            logger.__exit__()

    def test_interrupt_is_requested_once_for_one_turn(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            first = session.maybe_request_switch(session.active_turn, 2)
            second = session.maybe_request_switch(session.active_turn, 3)
            self.assertTrue(first)
            self.assertFalse(second)
            self.assertEqual(
                [method for _, method, _ in session.client.sent], ["turn/interrupt"]
            )
            logger.__exit__()

    def test_observe_records_no_interruption(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir, mode="observe")
            self.assertFalse(session.maybe_request_switch(session.active_turn, 2))
            self.assertEqual(session.client.sent, [])
            logger.__exit__()

    def test_switch_requires_explore_root_started_with_sol(self):
        cases = (
            {"explore": False},
            {"parent_thread_id": "parent-thread"},
            {"start_model": DEFAULT_ASTRA_MODEL},
            {"active_model": DEFAULT_ASTRA_MODEL},
        )
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmpdir:
                session, logger = make_session(
                    tmpdir, explore=case.get("explore", True)
                )
                if "active_model" in case:
                    session.active_turn.model = case["active_model"]
                for name, value in case.items():
                    if name != "active_model":
                        setattr(session.record, name, value)
                self.assertFalse(session.maybe_request_switch(session.active_turn, 2))
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
            self.assertFalse(session.maybe_request_switch(session.active_turn, 2))
            session.handle_notification(
                "item/completed",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "item": {"id": "command-1", "type": "commandExecution"},
                },
            )
            self.assertTrue(session.maybe_request_switch(session.active_turn, 2))
            self.assertEqual(
                [method for _, method, _ in session.client.sent], ["turn/interrupt"]
            )
            logger.__exit__()

    def test_interrupt_response_does_not_start_astra(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            self.assertTrue(session.maybe_request_switch(session.active_turn, 2))
            session.handle_response("turn/interrupt", {"result": {}})
            session.handle_notification(
                "turn/completed",
                {
                    "threadId": "thread-1",
                    "turn": {"id": "turn-1", "status": "interrupted"},
                },
            )
            self.assertFalse(
                any(method == "turn/start" for _, method, _ in session.client.sent)
            )
            logger.__exit__()

    def test_run_turns_are_serial_and_astra_cannot_switch(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.active_turn = None
            session.record.started_monotonic = time.monotonic()
            session.options.threshold_seconds = 0
            session.client.read_queue = [
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": "thread-1",
                        "turn": {"id": "turn-1", "status": "interrupted"},
                    },
                },
                {
                    "method": "turn/completed",
                    "params": {
                        "threadId": "thread-1",
                        "turn": {"id": "turn-2", "status": "completed"},
                    },
                },
            ]
            calls = []
            responses = iter(("turn-1", "turn-2"))

            def request_sync(method, params=None, timeout=30):
                calls.append((method, params))
                turn_id = next(responses)
                return {"result": {"turn": {"id": turn_id, "status": "inProgress"}}}

            session.request_sync = request_sync
            sol = session.run_turn(
                DEFAULT_SOL_MODEL,
                "medium",
                [{"type": "text", "text": "task"}],
                allow_switch=True,
            )
            astra = session.run_turn(
                DEFAULT_ASTRA_MODEL,
                "low",
                [{"type": "text", "text": "handoff"}],
                allow_switch=False,
            )
            self.assertTrue(sol.switch)
            self.assertEqual(astra.status, "completed")
            self.assertEqual(
                [params["model"] for method, params in calls if method == "turn/start"],
                [DEFAULT_SOL_MODEL, DEFAULT_ASTRA_MODEL],
            )
            self.assertEqual(
                sum(method == "turn/interrupt" for _, method, _ in session.client.sent),
                1,
            )
            logger.__exit__()

    def test_turn_start_response_cannot_reactivate_completed_turn(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.active_turn = None
            turn_ids = iter(("turn-1", "turn-2"))

            def request_sync(_method, _params=None, _timeout=30):
                turn_id = next(turn_ids)
                session.handle_notification(
                    "turn/started",
                    {
                        "threadId": "thread-1",
                        "turn": {"id": turn_id, "status": "inProgress"},
                    },
                )
                session.handle_notification(
                    "turn/completed",
                    {
                        "threadId": "thread-1",
                        "turn": {"id": turn_id, "status": "completed"},
                    },
                )
                return {"result": {"turn": {"id": turn_id, "status": "inProgress"}}}

            session.request_sync = request_sync
            first = session.run_turn(
                DEFAULT_SOL_MODEL,
                "medium",
                [{"type": "text", "text": "task"}],
                allow_switch=False,
            )
            second = session.run_turn(
                DEFAULT_ASTRA_MODEL,
                "low",
                [{"type": "text", "text": "handoff"}],
                allow_switch=False,
            )
            self.assertEqual((first.status, second.status), ("completed", "completed"))
            self.assertIsNone(session.active_turn)
            self.assertEqual(
                [turn.turn_id for turn in session.record.turns], ["turn-1", "turn-2"]
            )
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
            self.assertEqual(session.active_turn.agent_messages, {})
            logger.__exit__()

    def test_astra_partial_answer_is_not_replaced_by_sol(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.record.turns.append(
                TurnResult(
                    "turn-1",
                    DEFAULT_SOL_MODEL,
                    "interrupted",
                    True,
                    {"sol": {"text": "sol partial", "phase": None}},
                )
            )
            session.active_turn = TurnExecution(
                model=DEFAULT_ASTRA_MODEL,
                allow_switch=False,
                turn_id="turn-2",
                agent_messages={"astra": {"text": "astra partial", "phase": None}},
            )
            self.assertEqual(session.final_answer(), "astra partial")
            logger.__exit__()

    def test_failed_astra_start_is_not_reported_as_started(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.active_turn = None
            session.record.turns.append(
                TurnResult(
                    "turn-1",
                    DEFAULT_SOL_MODEL,
                    "interrupted",
                    True,
                    {"sol": {"text": "sol partial", "phase": None}},
                )
            )

            def rejected_start(_method, _params=None, _timeout=30):
                return {"error": {"message": "Astra rejected"}}

            session.request_sync = rejected_start
            with self.assertRaises(RuntimeError):
                session.run_turn(
                    DEFAULT_ASTRA_MODEL,
                    "low",
                    [{"type": "text", "text": "handoff"}],
                    allow_switch=False,
                )
            session.record.final_status = "failed"
            result = session.result()
            self.assertEqual(result["status"], "failed")
            self.assertEqual(result["switch"]["state"], "switch_incomplete")
            self.assertEqual(result["switch"]["count"], 0)
            self.assertEqual(result["models"]["execution"], [DEFAULT_SOL_MODEL])
            self.assertEqual(result["final_answer"], "")
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
            self.assertEqual(
                list(session.active_turn.agent_messages), ["progress", "answer"]
            )
            session.handle_notification(
                "turn/completed",
                {
                    "threadId": "thread-1",
                    "turn": {"id": "turn-1", "status": "completed"},
                },
            )
            session.finish_turn(session.active_turn)
            self.assertEqual(session.final_answer(), "final")
            logger.__exit__()

    def test_missing_usage_is_unknown_and_latest_only(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_notification(
                "thread/tokenUsage/updated",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "tokenUsage": {"total": {"totalTokens": 10}},
                },
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
                session.record.usage_by_thread["thread-1"]["token_usage"]["total"][
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
            session.record.completed_monotonic = session.record.started_monotonic + 1
            session.record.final_status = "completed"
            session.record.usage_by_thread = {
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
            session.record.usage_by_thread["child-thread"]["token_usage"] = {
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
