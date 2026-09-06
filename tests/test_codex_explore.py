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
    session.state.effective_model = DEFAULT_SOL_MODEL
    session.state.effective_model_source = "thread/start"
    session.state.configured_start_model = DEFAULT_SOL_MODEL
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

    def test_user_cancellation_never_restarts(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.state.user_cancelled = True
            session.start_fallback("test")
            self.assertFalse(session.state.fallback_steer_sent)
            logger.__exit__()

    def test_switch_is_sent_only_once(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.observe_threshold(2)
            session.maybe_switch(2)
            session.handle_response(
                "turn/settings/update", {"result": {"status": "applied"}}
            )
            session.maybe_switch(3)
            updates = [
                method
                for _, method, _ in session.client.sent
                if method == "turn/settings/update"
            ]
            self.assertEqual(updates, ["turn/settings/update"])
            self.assertEqual(session.state.switch_count, 1)
            logger.__exit__()

    def test_ineligible_contexts_do_not_switch(self):
        cases = (
            ("non-explore", {"explore": False}),
            ("non-sol", {"model": DEFAULT_ASTRA_MODEL}),
            ("child", {"parent": "parent-thread"}),
        )
        for name, case in cases:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as tmpdir:
                session, logger = make_session(
                    tmpdir, explore=case.get("explore", True)
                )
                if "model" in case:
                    session.state.effective_model = case["model"]
                if "parent" in case:
                    session.state.parent_thread_id = case["parent"]
                session.observe_threshold(2)
                session.maybe_switch(2)
                self.assertFalse(
                    any(
                        method == "turn/settings/update"
                        for _, method, _ in session.client.sent
                    )
                )
                logger.__exit__()

    def test_settings_failure_interrupts_once_then_starts_one_fallback_turn(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.observe_threshold(2)
            session.maybe_switch(2)
            session.handle_response(
                "turn/settings/update",
                {"error": {"code": -32601, "message": "unsupported"}},
            )
            self.assertTrue(session.state.fallback_steer_sent)
            session.handle_response("turn/steer", {"result": {"turnId": "turn-1"}})
            session.interrupt_deadline = 0
            session.maybe_interrupt_fallback(1)
            session.maybe_interrupt_fallback(2)
            self.assertEqual(
                [method for _, method, _ in session.client.sent].count(
                    "turn/interrupt"
                ),
                1,
            )
            session.handle_response("turn/interrupt", {"result": {}})
            session.handle_turn_completed({"id": "turn-1", "status": "interrupted"})
            self.assertFalse(session.state.fallback_turn_started)
            self.assertEqual(
                [method for _, method, _ in session.client.sent].count("turn/start"), 1
            )
            logger.__exit__()

    def test_usage_snapshots_are_not_summed_and_confirm_astra(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            usage = {
                "total": {
                    "inputTokens": 20,
                    "cachedInputTokens": 5,
                    "cacheWriteInputTokens": 0,
                    "outputTokens": 10,
                    "reasoningOutputTokens": 3,
                    "totalTokens": 30,
                }
            }
            event = {"threadId": "thread-1", "turnId": "turn-1", "tokenUsage": usage}
            session.handle_notification("thread/tokenUsage/updated", event)
            session.handle_notification("thread/tokenUsage/updated", event)
            self.assertEqual(len(session.state.usage_snapshots), 2)
            self.assertIsNone(session.state.astra_execution_confirmed)
            session.state.request_accepted = True
            session.observe_account_usage_models(
                {
                    "threadUsage": {
                        "groups": [
                            {"model": DEFAULT_SOL_MODEL},
                            {"model": DEFAULT_ASTRA_MODEL},
                        ]
                    }
                }
            )
            self.assertTrue(session.state.astra_execution_confirmed)
            self.assertEqual(
                session.state.models_observed, [DEFAULT_SOL_MODEL, DEFAULT_ASTRA_MODEL]
            )
            logger.__exit__()

    def test_notifications_from_other_thread_or_turn_are_ignored(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_notification(
                "item/agentMessage/delta",
                {
                    "threadId": "child-thread",
                    "turnId": "turn-1",
                    "itemId": "child-item",
                    "delta": "child",
                },
            )
            session.handle_notification(
                "item/agentMessage/delta",
                {
                    "threadId": "thread-1",
                    "turnId": "old-turn",
                    "itemId": "old-item",
                    "delta": "old",
                },
            )
            session.handle_notification(
                "thread/tokenUsage/updated",
                {
                    "threadId": "thread-1",
                    "turnId": "old-turn",
                    "tokenUsage": {"total": {"totalTokens": 9}},
                },
            )
            self.assertEqual(session.state.agent_messages, {})
            self.assertEqual(session.state.usage_snapshots, [])
            logger.__exit__()

    def test_fallback_turn_is_monitored_after_interrupted_turn(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.state.fallback_interrupt_attempted = True
            session.handle_turn_completed({"id": "turn-1", "status": "interrupted"})
            self.assertTrue(session.state.fallback_turn_pending)
            self.assertIsNone(session.state.active_turn_id)
            session.handle_response(
                "turn/start",
                {"result": {"turn": {"id": "turn-2", "status": "inProgress"}}},
            )
            self.assertFalse(session.state.fallback_turn_pending)
            self.assertTrue(session.state.fallback_turn_started)
            self.assertEqual(session.state.active_turn_id, "turn-2")
            logger.__exit__()

    def test_final_answer_excludes_progress_and_previous_turn(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.handle_notification(
                "item/agentMessage/delta",
                {
                    "threadId": "thread-1",
                    "turnId": "turn-1",
                    "itemId": "progress",
                    "delta": "progress",
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
                        "text": "progress",
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
                        "text": "final",
                        "phase": "final_answer",
                    },
                },
            )
            session.handle_turn_completed({"id": "turn-1", "status": "completed"})
            self.assertEqual(session.result()["final_answer"], "final")
            logger.__exit__()

    def test_usage_model_groups_do_not_claim_last_group_as_effective(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            session, logger = make_session(tmpdir)
            session.state.request_accepted = True
            session.observe_account_usage_models(
                {
                    "threadUsage": {
                        "groups": [
                            {"model": DEFAULT_SOL_MODEL},
                            {"model": DEFAULT_ASTRA_MODEL},
                        ]
                    }
                }
            )
            self.assertIsNone(session.state.effective_model)
            self.assertEqual(session.state.effective_model_source, "ambiguous_usage")
            logger.__exit__()
