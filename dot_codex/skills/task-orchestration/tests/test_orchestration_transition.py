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
STATE_SPEC = importlib.util.spec_from_file_location(
    "orchestration_state_for_transition_test",
    SKILL_ROOT / "scripts" / "orchestration_state.py",
)
storage = importlib.util.module_from_spec(STATE_SPEC)
STATE_SPEC.loader.exec_module(storage)
scripts_root = str(SKILL_ROOT / "scripts")
if scripts_root not in sys.path:
    sys.path.insert(0, scripts_root)
TRANSITION_SPEC = importlib.util.spec_from_file_location(
    "orchestration_transition",
    SKILL_ROOT / "scripts" / "orchestration_transition.py",
)
transition = importlib.util.module_from_spec(TRANSITION_SPEC)
TRANSITION_SPEC.loader.exec_module(transition)
NOTIFICATION_SPEC = importlib.util.spec_from_file_location(
    "completion_notification_for_transition_test",
    SKILL_ROOT.parent / "completion-report" / "scripts" / "completion_notification.py",
)
notification_outbox = importlib.util.module_from_spec(NOTIFICATION_SPEC)
NOTIFICATION_SPEC.loader.exec_module(notification_outbox)


class OrchestrationTransitionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.config_home = self.root / "config"
        self.state_home = self.root / "state"
        config_directory = self.config_home / "codex-task-orchestrator"
        config_directory.mkdir(parents=True)
        (config_directory / "config.toml").write_text(
            """
[orchestrations.example]
parent_thread_id = "parent-thread"
repository = "owner/repository"
pull_request_repositories = ["owner/repository"]
task_source = "file:///tasks.md"
""".strip()
            + "\n"
        )
        self.environment = patch.dict(
            os.environ,
            {
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
            },
        )
        self.environment.start()
        self.cli_environment = {
            **os.environ,
            "XDG_CONFIG_HOME": str(self.config_home),
            "XDG_STATE_HOME": str(self.state_home),
        }

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def task_map(self, tasks):
        return storage.normalize_tasks({"tasks": tasks})

    def new_state(self, tasks, completed=None, maximum_parallelism=1):
        state = transition.initial_state(
            "source-1",
            self.task_map(tasks),
            completed or [],
            maximum_parallelism,
            "manual",
        )
        return transition.materialize_next("example", state)

    def event(self, state, event_type, **fields):
        action = transition.action_name(state)
        if event_type in {"thread_created", "thread_verified"}:
            fields.setdefault("repository", "owner/repository")
        return {
            "type": event_type,
            "action_token": transition.action_token(state, action),
            "source_revision": state["source_revision"],
            **fields,
        }

    def apply(self, state, event_type, **fields):
        state = transition.reduce_event(
            "example", state, self.event(state, event_type, **fields)
        )
        return transition.materialize_next("example", state)

    def run_cli(self, command):
        return subprocess.run(
            command,
            capture_output=True,
            check=False,
            text=True,
            env=self.cli_environment,
        )

    def create_tracked_session(self, task_id="A", number=42):
        storage.reserve_session("example", task_id)
        storage.record_session("example", task_id, f"thread-{task_id.lower()}")
        storage.record_pull_request("example", task_id, "owner/repository", number)

    def notification(self, task_id="A", number=42, merge_commit=None):
        return notification_outbox.build_notification(
            "example",
            task_id,
            "owner/repository",
            number,
            merge_commit or "a" * 40,
        )

    def save_note(self, task_id, note):
        path = self.root / f"{task_id}-note.json"
        path.write_text(json.dumps(note))
        storage.record_completion_note("example", task_id, path)

    def advance_to_created_thread(self, task_id="A"):
        state, _ = self.new_state([{"id": task_id, "dependencies": []}])
        self.assertEqual(transition.action_name(state), "reserve_session")
        storage.reserve_session("example", task_id)
        state, _ = self.apply(
            state,
            "session_reserved",
            task_id=task_id,
        )
        self.assertEqual(transition.action_name(state), "create_thread")
        state, plan = self.apply(
            state,
            "thread_created",
            task_id=task_id,
            thread_id="created-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
        )
        return state, plan

    def advance_to_recorded_session(self):
        state, _ = self.advance_to_created_thread()
        state, _ = self.apply(
            state,
            "thread_verified",
            task_id="A",
            thread_id="created-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
            verified=True,
        )
        storage.record_session("example", "A", "created-thread")
        return self.apply(
            state,
            "session_recorded",
            task_id="A",
            thread_id="created-thread",
        )

    def test_returns_one_action_for_each_launch_stage(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        self.assertEqual(transition.action_name(state), "reserve_session")

        storage.reserve_session("example", "A")
        state, _ = self.apply(state, "session_reserved", task_id="A")
        self.assertEqual(transition.action_name(state), "create_thread")

        state, _ = self.apply(
            state,
            "thread_created",
            task_id="A",
            thread_id="created-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
        )
        self.assertEqual(transition.action_name(state), "verify_thread")

        state, _ = self.apply(
            state,
            "thread_verified",
            task_id="A",
            thread_id="created-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
            verified=True,
        )
        self.assertEqual(transition.action_name(state), "record_session")

        storage.record_session("example", "A", "created-thread")
        state, _ = self.apply(
            state,
            "session_recorded",
            task_id="A",
            thread_id="created-thread",
        )
        self.assertEqual(transition.action_name(state), "set_thread_title")

        state, plan = self.apply(
            state,
            "thread_title_set",
            task_id="A",
            thread_id="created-thread",
            title="[A] First task",
        )
        self.assertEqual(transition.action_name(state), "complete")
        self.assertIsNone(state["launch"])
        self.assertEqual(
            state["launch_history"],
            [
                {
                    "task_id": "A",
                    "thread": {
                        "thread_id": "created-thread",
                        "host_id": "local",
                        "project_id": "saved-project",
                        "checkout": "/checkout/repository",
                    },
                }
            ],
        )
        self.assertEqual(
            transition.output("example", state, plan)["details"]["launched"],
            state["launch_history"],
        )

    def test_wait_state_persists_turn_cursor_and_replans_after_note(self):
        self.create_tracked_session()
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ],
            completed=["A"],
        )
        self.assertEqual(transition.action_name(state), "recover_completion_note")

        state, _ = self.apply(
            state,
            "completion_recovery_requested",
            task_id="A",
            child_thread_id="thread-a",
            turn_id="recovery-turn",
            wait_cursor="cursor-1",
        )
        self.assertEqual(transition.action_name(state), "wait_completion_note")
        self.assertEqual(state["recovery"]["turn_id"], "recovery-turn")

        state, _ = self.apply(
            state,
            "completion_waited",
            task_id="A",
            turn_id="recovery-turn",
            outcome="timed_out",
            wait_cursor="cursor-2",
        )
        self.assertEqual(transition.action_name(state), "wait_completion_note")
        self.assertEqual(state["recovery"]["wait_cursor"], "cursor-2")

        path = transition.transition_path("example")
        transition.write_state(path, state)
        state = transition.load_state(path)
        self.assertEqual(state["recovery"]["wait_cursor"], "cursor-2")

        self.save_note("A", {"handoff": "Use the persisted interface."})
        state, _ = self.apply(
            state,
            "completion_waited",
            task_id="A",
            turn_id="recovery-turn",
            outcome="completed",
            wait_cursor="cursor-3",
        )
        self.assertEqual(transition.action_name(state), "reserve_session")
        self.assertEqual(state["launch"]["task_id"], "B")
        self.assertEqual(
            state["launch"]["dependency_completion_notes"],
            {"A": {"handoff": "Use the persisted interface."}},
        )

    def test_created_thread_identity_survives_parent_restart(self):
        state, plan = self.advance_to_created_thread()
        path = transition.transition_path("example")
        transition.write_state(path, state)

        restarted = transition.load_state(path)
        output = transition.output("example", restarted, plan)

        self.assertEqual(output["action"], "verify_thread")
        self.assertEqual(
            output["details"]["thread"],
            {
                "thread_id": "created-thread",
                "host_id": "local",
                "project_id": "saved-project",
                "checkout": "/checkout/repository",
            },
        )
        self.assertNotIn("thread_created", output["allowed_events"])

    def assert_retry_preserves_thread(self, operation, factory):
        state, _ = factory()
        original_thread = json.loads(json.dumps(state["launch"]["thread"]))

        state, plan = self.apply(
            state,
            "operation_failed",
            operation=operation,
            message=f"{operation} failed",
            retryable=True,
        )

        self.assertEqual(transition.action_name(state), "stop")
        self.assertEqual(state["launch"]["thread"], original_thread)
        output = transition.output("example", state, plan)
        self.assertEqual(output["details"]["operation"], operation)

        state, _ = self.apply(state, "retry_requested")
        self.assertEqual(transition.action_name(state), operation)
        self.assertEqual(state["launch"]["thread"], original_thread)

    def test_project_verification_failure_preserves_created_thread(self):
        self.assert_retry_preserves_thread(
            "verify_thread", self.advance_to_created_thread
        )

    def test_session_record_failure_preserves_created_thread(self):
        self.assert_retry_preserves_thread(
            "record_session", self._advance_to_verified_thread
        )

    def test_title_failure_preserves_created_thread(self):
        self.assert_retry_preserves_thread(
            "set_thread_title", self.advance_to_recorded_session
        )

    def test_operation_failures_preserve_current_task_and_retry_policy(self):
        reserve_state, _ = self.new_state([{"id": "A", "dependencies": []}])
        reserve_state, reserve_plan = self.apply(
            reserve_state,
            "operation_failed",
            operation="reserve_session",
            message="reservation failed",
            retryable=True,
        )
        self.assertEqual(transition.action_name(reserve_state), "stop")
        self.assertEqual(
            transition.output("example", reserve_state, reserve_plan)["details"][
                "task_id"
            ],
            "A",
        )

        self.create_tracked_session()
        recovery_state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ],
            completed=["A"],
        )
        recovery_state, recovery_plan = self.apply(
            recovery_state,
            "operation_failed",
            operation="recover_completion_note",
            message="recovery request failed",
            retryable=False,
        )
        recovery_output = transition.output("example", recovery_state, recovery_plan)
        self.assertEqual(recovery_output["action"], "stop")
        self.assertEqual(recovery_output["details"]["task_id"], "A")
        self.assertNotIn("retry_requested", recovery_output["allowed_events"])

        waiting_state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ],
            completed=["A"],
        )
        waiting_state, _ = self.apply(
            waiting_state,
            "completion_recovery_requested",
            task_id="A",
            child_thread_id="thread-a",
            turn_id="turn-a",
            wait_cursor=None,
        )
        waiting_state, waiting_plan = self.apply(
            waiting_state,
            "operation_failed",
            operation="wait_completion_note",
            message="wait failed",
            retryable=True,
        )
        waiting_output = transition.output("example", waiting_state, waiting_plan)
        self.assertEqual(waiting_output["action"], "stop")
        self.assertEqual(waiting_output["details"]["task_id"], "A")

    def test_completion_wait_outcomes_set_retry_policy(self):
        self.create_tracked_session()
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ],
            completed=["A"],
        )
        state, _ = self.apply(
            state,
            "completion_recovery_requested",
            task_id="A",
            child_thread_id="thread-a",
            turn_id="turn-a",
            wait_cursor="cursor-a",
        )

        for outcome, retryable in (("needs_attention", True), ("failed", False)):
            with self.subTest(outcome=outcome):
                candidate = json.loads(json.dumps(state))
                candidate, plan = self.apply(
                    candidate,
                    "completion_waited",
                    task_id="A",
                    turn_id="turn-a",
                    outcome=outcome,
                    wait_cursor=f"cursor-{outcome}",
                )
                output = transition.output("example", candidate, plan)
                self.assertEqual(output["action"], "stop")
                self.assertEqual(output["details"]["retryable"], retryable)

    def test_non_retryable_stop_requires_confirmed_reservation_release(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        storage.reserve_session("example", "A")
        state, _ = self.apply(state, "session_reserved", task_id="A")
        with self.assertRaisesRegex(
            transition.TransitionError, "not directly retryable"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "operation_failed",
                    operation="create_thread",
                    message="thread creation failed",
                    retryable=True,
                ),
            )
        state, plan = self.apply(
            state,
            "operation_failed",
            operation="create_thread",
            message="thread creation result is unknown",
            retryable=False,
        )

        output = transition.output("example", state, plan)
        self.assertEqual(output["details"]["task_id"], "A")
        self.assertNotIn("retry_requested", output["allowed_events"])
        self.assertIn("reservation_released", output["allowed_events"])
        legacy_state = json.loads(json.dumps(state))
        legacy_state["stop"]["retryable"] = True
        self.assertNotIn(
            "retry_requested",
            transition.event_schemas("stop", transition.normalize_state(legacy_state)),
        )
        with self.assertRaisesRegex(
            transition.TransitionError, "invalid for action stop"
        ):
            transition.reduce_event(
                "example", state, self.event(state, "retry_requested")
            )

        storage.release_reservation("example", "A")
        state, _ = self.apply(state, "reservation_released", task_id="A")

        self.assertEqual(transition.action_name(state), "reserve_session")
        self.assertEqual(state["launch"]["status"], "selected")

    def _advance_to_verified_thread(self):
        state, _ = self.advance_to_created_thread()
        return self.apply(
            state,
            "thread_verified",
            task_id="A",
            thread_id="created-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
            verified=True,
        )

    def test_reservation_restart_does_not_select_or_reserve_again(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        storage.reserve_session("example", "A")
        path = transition.transition_path("example")
        transition.write_state(path, state)

        restarted = transition.load_state(path)
        self.assertEqual(transition.action_name(restarted), "reserve_session")
        state, plan = self.apply(restarted, "session_reserved", task_id="A")
        output = transition.output("example", state, plan)

        self.assertEqual(output["action"], "create_thread")
        self.assertEqual(output["details"]["task_id"], "A")
        with self.assertRaisesRegex(
            storage.StateError, "already has session creation state"
        ):
            storage.reserve_session("example", "A")

    def test_create_result_can_be_recovered_before_session_mapping(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        storage.reserve_session("example", "A")
        state, _ = self.apply(state, "session_reserved", task_id="A")
        path = transition.transition_path("example")
        transition.write_state(path, state)

        restarted = transition.load_state(path)
        self.assertEqual(transition.action_name(restarted), "create_thread")
        recovered, plan = self.apply(
            restarted,
            "thread_created",
            task_id="A",
            thread_id="recovered-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
        )
        output = transition.output("example", recovered, plan)

        self.assertEqual(output["action"], "verify_thread")
        self.assertEqual(output["details"]["thread"]["thread_id"], "recovered-thread")
        load_task = storage.load_sessions(
            storage.state_path("example"),
            "parent-thread",
            ["owner/repository"],
        )["tasks"]["A"]
        self.assertEqual(load_task, {"creation": {"status": "reserved"}})
        self.assertNotIn("child_thread_id", load_task)

    def test_saved_note_can_be_observed_before_recovery_request(self):
        self.create_tracked_session()
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ],
            completed=["A"],
        )
        self.assertEqual(transition.action_name(state), "recover_completion_note")
        self.save_note("A", {})

        state, _ = self.apply(
            state,
            "completion_note_observed",
            task_id="A",
        )

        self.assertEqual(transition.action_name(state), "reserve_session")
        self.assertEqual(state["launch"]["task_id"], "B")

    def test_completion_notification_replans_and_deduplicates_launch(self):
        self.create_tracked_session()
        self.save_note("A", {"handoff": "Use the notified interface."})
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ]
        )
        self.assertEqual(transition.action_name(state), "reserve_session")
        self.assertEqual(state["launch"]["task_id"], "B")

        state, _ = self.apply(
            state,
            "completion_notified",
            notification=self.notification(),
            observed_merge_commit="a" * 40,
        )

        self.assertEqual(transition.action_name(state), "reserve_session")
        self.assertEqual(state["launch"]["task_id"], "B")
        self.assertEqual(state["completed"], ["A"])
        self.assertEqual(list(state["notifications"]), ["A"])

        state, _ = self.apply(
            state,
            "completion_notified",
            notification=self.notification(),
            observed_merge_commit="a" * 40,
        )
        self.assertEqual(transition.action_name(state), "reserve_session")
        self.assertEqual(state["launch"]["task_id"], "B")
        self.assertEqual(list(state["notifications"]), ["A"])

    def test_completion_notification_preserves_in_flight_thread_token(self):
        self.create_tracked_session()
        self.save_note("A", {})
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": []},
            ],
            maximum_parallelism=2,
        )
        self.assertEqual(state["launch"]["task_id"], "B")
        storage.reserve_session("example", "B")
        state, _ = self.apply(state, "session_reserved", task_id="B")
        token = transition.action_token(state, "create_thread")
        sequence = state["sequence"]
        thread_created = self.event(
            state,
            "thread_created",
            task_id="B",
            thread_id="thread-b",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
        )

        state = transition.reduce_event(
            "example",
            state,
            self.event(
                state,
                "completion_notified",
                notification=self.notification(),
                observed_merge_commit="a" * 40,
            ),
        )

        self.assertEqual(state["sequence"], sequence)
        self.assertEqual(transition.action_token(state, "create_thread"), token)
        state = transition.reduce_event("example", state, thread_created)
        self.assertEqual(transition.action_name(state), "verify_thread")
        self.assertEqual(state["launch"]["thread"]["thread_id"], "thread-b")

    def test_thread_events_reject_disallowed_repository(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        storage.reserve_session("example", "A")
        state, _ = self.apply(state, "session_reserved", task_id="A")
        with self.assertRaisesRegex(
            transition.TransitionError, "repository is not allowed"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "thread_created",
                    task_id="A",
                    repository="untrusted/repository",
                    thread_id="thread-a",
                    host_id="local",
                    project_id="untrusted-project",
                    checkout="/checkout/untrusted",
                ),
            )

        state, _ = self.apply(
            state,
            "thread_created",
            task_id="A",
            thread_id="thread-a",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
        )
        with self.assertRaisesRegex(
            transition.TransitionError, "repository is not allowed"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "thread_verified",
                    task_id="A",
                    repository="untrusted/repository",
                    thread_id="thread-a",
                    host_id="local",
                    project_id="saved-project",
                    checkout="/checkout/repository",
                    verified=True,
                ),
            )

    def test_completion_notification_rejects_changed_or_unverified_payload(self):
        self.create_tracked_session()
        self.save_note("A", {})
        state, _ = self.new_state([{"id": "A", "dependencies": []}])

        with self.assertRaisesRegex(
            transition.TransitionError, "does not match the observed merge"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "completion_notified",
                    notification=self.notification(),
                    observed_merge_commit="b" * 40,
                ),
            )

        state, _ = self.apply(
            state,
            "completion_notified",
            notification=self.notification(),
            observed_merge_commit="a" * 40,
        )
        with self.assertRaisesRegex(transition.TransitionError, "already has another"):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "completion_notified",
                    notification=self.notification(merge_commit="b" * 40),
                    observed_merge_commit="b" * 40,
                ),
            )

    def test_completion_notification_requires_saved_note_and_exact_schema(self):
        self.create_tracked_session()
        state, _ = self.new_state([{"id": "A", "dependencies": []}])

        with self.assertRaisesRegex(
            transition.TransitionError, "no saved Completion Note"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "completion_notified",
                    notification=self.notification(),
                    observed_merge_commit="a" * 40,
                ),
            )

        invalid = {**self.notification(), "note": {"handoff": "must not pass"}}
        with self.assertRaisesRegex(
            transition.TransitionError, "missing or unknown fields"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "completion_notified",
                    notification=invalid,
                    observed_merge_commit="a" * 40,
                ),
            )

        invalid_pull_request = self.notification()
        invalid_pull_request["pull_request"]["extra"] = "must not pass"
        with self.assertRaisesRegex(
            transition.TransitionError, "missing or unknown fields"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "completion_notified",
                    notification=invalid_pull_request,
                    observed_merge_commit="a" * 40,
                ),
            )

    def test_rejects_notification_missing_from_completed_tasks(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        malformed = json.loads(json.dumps(state))
        malformed["notifications"]["A"] = self.notification()

        with self.assertRaisesRegex(
            transition.TransitionError, "notification task is not completed"
        ):
            transition.normalize_state(malformed)

    def test_rejects_stale_source_observation_and_contradictory_thread(self):
        state, _ = self.advance_to_created_thread()
        stale_source = self.event(
            state,
            "thread_verified",
            task_id="A",
            thread_id="created-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
            verified=True,
        )
        stale_source["source_revision"] = "source-0"
        with self.assertRaisesRegex(transition.TransitionError, "stale task source"):
            transition.reduce_event("example", state, stale_source)

        with self.assertRaisesRegex(
            transition.TransitionError, "does not match the created thread"
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(
                    state,
                    "thread_verified",
                    task_id="A",
                    thread_id="another-thread",
                    host_id="local",
                    project_id="saved-project",
                    checkout="/checkout/repository",
                    verified=True,
                ),
            )

        old_event = self.event(
            state,
            "thread_verified",
            task_id="A",
            thread_id="created-thread",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
            verified=True,
        )
        advanced = transition.reduce_event("example", state, old_event)
        with self.assertRaisesRegex(
            transition.TransitionError, "stale external observation"
        ):
            transition.reduce_event("example", advanced, old_event)

    def test_rejects_unknown_state_and_task_source_change_mid_operation(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        malformed = json.loads(json.dumps(state))
        malformed["launch"]["status"] = "unknown"
        with self.assertRaisesRegex(transition.TransitionError, "unknown launch"):
            transition.normalize_state(malformed)

        changed = self.task_map(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": []},
            ]
        )
        self.assertFalse(
            transition.same_inputs(state, "source-2", changed, [], 1, "manual")
        )
        self.assertNotEqual(transition.action_name(state), "complete")

    def test_rejects_session_mapping_that_disagrees_with_persisted_stage(self):
        state, _ = self.advance_to_created_thread()
        sessions_path = storage.state_path("example")
        sessions_path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "parent_thread_id": "parent-thread",
                    "tasks": {
                        "A": {"child_thread_id": "another-thread"},
                    },
                }
            )
        )

        with self.assertRaisesRegex(
            transition.TransitionError, "lost its session reservation"
        ):
            transition.materialize_next("example", state)

    def test_rejects_selected_launch_with_an_existing_child_thread(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])
        storage.reserve_session("example", "A")
        storage.record_session("example", "A", "unexpected-thread")

        with self.assertRaisesRegex(
            transition.TransitionError,
            "selected launch conflicts with the session mapping",
        ):
            transition.materialize_next("example", state)

    def test_rejects_recovery_with_a_changed_child_thread(self):
        self.create_tracked_session()
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ],
            completed=["A"],
        )
        sessions_path = storage.state_path("example")
        sessions = storage.load_sessions(
            sessions_path, "parent-thread", ["owner/repository"]
        )
        sessions["tasks"]["A"]["child_thread_id"] = "unexpected-thread"
        storage.write_sessions(sessions_path, sessions)

        with self.assertRaisesRegex(
            transition.TransitionError,
            "recovery state does not match the session mapping",
        ):
            transition.materialize_next("example", state)

    def test_rejects_verified_launch_with_another_recorded_thread(self):
        state, _ = self._advance_to_verified_thread()
        storage.record_session("example", "A", "unexpected-thread")

        with self.assertRaisesRegex(
            transition.TransitionError,
            "verified launch conflicts with the session mapping",
        ):
            transition.materialize_next("example", state)

    def test_rejects_recorded_launch_with_a_changed_child_thread(self):
        state, _ = self.advance_to_recorded_session()
        sessions_path = storage.state_path("example")
        sessions = storage.load_sessions(
            sessions_path, "parent-thread", ["owner/repository"]
        )
        sessions["tasks"]["A"]["child_thread_id"] = "unexpected-thread"
        storage.write_sessions(sessions_path, sessions)

        with self.assertRaisesRegex(
            transition.TransitionError,
            "recorded launch does not match the session mapping",
        ):
            transition.materialize_next("example", state)

    def test_rejects_event_for_another_current_task(self):
        state, _ = self.new_state([{"id": "A", "dependencies": []}])

        with self.assertRaisesRegex(
            transition.TransitionError,
            "event task does not match the current operation",
        ):
            transition.reduce_event(
                "example",
                state,
                self.event(state, "session_reserved", task_id="B"),
            )

    def test_parallelism_dependencies_and_order_still_come_from_plan(self):
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": [], "order": 1},
                {"id": "B", "dependencies": [], "order": 0},
                {"id": "C", "dependencies": ["A", "B"], "order": 2},
            ],
            maximum_parallelism=2,
        )
        self.assertEqual(state["launch"]["task_id"], "B")

        storage.reserve_session("example", "B")
        state, _ = self.apply(state, "session_reserved", task_id="B")
        state, _ = self.apply(
            state,
            "thread_created",
            task_id="B",
            thread_id="thread-b",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
        )
        state, _ = self.apply(
            state,
            "thread_verified",
            task_id="B",
            thread_id="thread-b",
            host_id="local",
            project_id="saved-project",
            checkout="/checkout/repository",
            verified=True,
        )
        storage.record_session("example", "B", "thread-b")
        state, _ = self.apply(
            state,
            "session_recorded",
            task_id="B",
            thread_id="thread-b",
        )
        state, plan = self.apply(
            state,
            "thread_title_set",
            task_id="B",
            thread_id="thread-b",
            title="[B] Second task",
        )

        self.assertEqual(transition.action_name(state), "reserve_session")
        self.assertEqual(state["launch"]["task_id"], "A")
        self.assertEqual(plan["waiting_dependencies"], {"C": ["A", "B"]})

    def test_cli_init_is_idempotent_and_rejects_source_drift(self):
        tasks = self.root / "tasks.json"
        tasks.write_text(json.dumps({"tasks": [{"id": "A", "dependencies": []}]}))
        command = [
            sys.executable,
            str(TRANSITION_SPEC.origin),
            "init",
            "example",
            "--tasks",
            str(tasks),
            "--max-parallelism",
            "1",
            "--policy",
            "manual",
            "--source-revision",
            "source-1",
        ]
        first = self.run_cli(command)
        second = self.run_cli(command)
        stale = self.run_cli([*command[:-1], "source-2"])

        self.assertEqual(first.returncode, 0)
        self.assertEqual(second.returncode, 0)
        self.assertEqual(json.loads(first.stdout), json.loads(second.stdout))
        self.assertEqual(json.loads(first.stdout)["policy"], "manual")
        self.assertEqual(stale.returncode, 2)
        self.assertEqual(
            json.loads(stale.stderr),
            {"error": "cycle inputs changed during an active operation"},
        )

    def test_cli_next_and_apply_event_enforce_replay_boundaries(self):
        tasks = self.root / "tasks.json"
        tasks.write_text(json.dumps({"tasks": [{"id": "A", "dependencies": []}]}))
        init = self.run_cli(
            [
                sys.executable,
                str(TRANSITION_SPEC.origin),
                "init",
                "example",
                "--tasks",
                str(tasks),
                "--max-parallelism",
                "1",
                "--policy",
                "manual",
                "--source-revision",
                "source-1",
            ]
        )
        self.assertEqual(init.returncode, 0)
        storage.reserve_session("example", "A")
        state = transition.load_state(transition.transition_path("example"))
        event = self.event(state, "session_reserved", task_id="A")
        event_path = self.root / "session-reserved.json"
        event_path.write_text(json.dumps(event))
        apply_command = [
            sys.executable,
            str(TRANSITION_SPEC.origin),
            "apply-event",
            "example",
            "--source-revision",
            "source-1",
            "--event-file",
            str(event_path),
        ]

        first = self.run_cli(apply_command)
        replay = self.run_cli(apply_command)
        current = self.run_cli(
            [
                sys.executable,
                str(TRANSITION_SPEC.origin),
                "next",
                "example",
                "--source-revision",
                "source-1",
            ]
        )
        stale = self.run_cli(
            [
                sys.executable,
                str(TRANSITION_SPEC.origin),
                "next",
                "example",
                "--source-revision",
                "source-0",
            ]
        )
        conflicting_path = self.root / "conflicting-event.json"
        conflicting_path.write_text(
            json.dumps(
                {
                    **event,
                    "type": "operation_failed",
                    "operation": "reserve_session",
                    "message": "conflicting replay",
                    "retryable": True,
                    "task_id": "A",
                }
            )
        )
        conflicting = self.run_cli([*apply_command[:-1], str(conflicting_path)])
        non_object_path = self.root / "non-object-event.json"
        non_object_path.write_text("[]")
        non_object = self.run_cli([*apply_command[:-1], str(non_object_path)])

        self.assertEqual(first.returncode, 0)
        self.assertEqual(replay.returncode, 0)
        self.assertEqual(current.returncode, 0)
        self.assertEqual(json.loads(first.stdout), json.loads(replay.stdout))
        self.assertEqual(json.loads(first.stdout), json.loads(current.stdout))
        self.assertEqual(stale.returncode, 2)
        self.assertEqual(
            json.loads(stale.stderr), {"error": "task source revision is stale"}
        )
        self.assertEqual(conflicting.returncode, 2)
        self.assertEqual(
            json.loads(conflicting.stderr),
            {"error": "action token was reused with a different event"},
        )
        self.assertEqual(non_object.returncode, 2)
        self.assertEqual(
            json.loads(non_object.stderr),
            {"error": "orchestration event must be an object"},
        )

    def test_concurrent_notification_and_action_event_preserve_both_results(self):
        self.create_tracked_session()
        self.save_note("A", {})
        state, _ = self.new_state(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": []},
            ],
            maximum_parallelism=2,
        )
        storage.reserve_session("example", "B")
        state, _ = self.apply(state, "session_reserved", task_id="B")
        transition.write_state(transition.transition_path("example"), state)

        notification_path = self.root / "notification-event.json"
        notification_path.write_text(
            json.dumps(
                self.event(
                    state,
                    "completion_notified",
                    notification=self.notification(),
                    observed_merge_commit="a" * 40,
                )
            )
        )
        thread_path = self.root / "thread-event.json"
        thread_path.write_text(
            json.dumps(
                self.event(
                    state,
                    "thread_created",
                    task_id="B",
                    thread_id="thread-b",
                    host_id="local",
                    project_id="saved-project",
                    checkout="/checkout/repository",
                )
            )
        )
        processes = [
            subprocess.Popen(
                [
                    sys.executable,
                    str(TRANSITION_SPEC.origin),
                    "apply-event",
                    "example",
                    "--source-revision",
                    "source-1",
                    "--event-file",
                    str(event_path),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=self.cli_environment,
            )
            for event_path in (notification_path, thread_path)
        ]
        results = [process.communicate() for process in processes]

        self.assertEqual([process.returncode for process in processes], [0, 0], results)
        persisted = transition.load_state(transition.transition_path("example"))
        self.assertEqual(list(persisted["notifications"]), ["A"])
        self.assertEqual(transition.action_name(persisted), "verify_thread")
        self.assertEqual(persisted["launch"]["thread"]["thread_id"], "thread-b")

    def test_cli_init_changes_cycle_before_old_plan_is_materialized(self):
        self.create_tracked_session()
        tasks = self.root / "tasks.json"
        tasks.write_text(json.dumps({"tasks": [{"id": "A", "dependencies": []}]}))
        command = [
            sys.executable,
            str(TRANSITION_SPEC.origin),
            "init",
            "example",
            "--tasks",
            str(tasks),
            "--max-parallelism",
            "1",
            "--policy",
            "manual",
            "--source-revision",
            "source-1",
        ]
        first = self.run_cli(command)
        self.assertEqual(first.returncode, 0)
        self.assertEqual(json.loads(first.stdout)["action"], "complete")

        self.save_note("A", {})
        tasks.write_text(
            json.dumps(
                {
                    "tasks": [
                        {"id": "A", "dependencies": []},
                        {"id": "B", "dependencies": ["A"]},
                    ]
                }
            )
        )
        changed = self.run_cli([*command[:-1], "source-2"])

        self.assertEqual(changed.returncode, 0)
        output = json.loads(changed.stdout)
        self.assertEqual(output["source_revision"], "source-2")
        self.assertEqual(output["action"], "reserve_session")

    def test_cli_init_normalizes_note_completion_after_notification(self):
        self.create_tracked_session()
        tasks = self.root / "tasks.json"
        tasks.write_text(
            json.dumps(
                {
                    "tasks": [
                        {"id": "A", "dependencies": []},
                        {"id": "B", "dependencies": ["A"]},
                    ]
                }
            )
        )
        command = [
            sys.executable,
            str(TRANSITION_SPEC.origin),
            "init",
            "example",
            "--tasks",
            str(tasks),
            "--max-parallelism",
            "1",
            "--policy",
            "manual",
            "--source-revision",
            "source-1",
        ]
        first = self.run_cli(command)
        self.assertEqual(first.returncode, 0)
        self.assertEqual(json.loads(first.stdout)["action"], "complete")

        self.save_note("A", {})
        state = transition.load_state(transition.transition_path("example"))
        event_path = self.root / "completion-notified.json"
        event_path.write_text(
            json.dumps(
                self.event(
                    state,
                    "completion_notified",
                    notification=self.notification(),
                    observed_merge_commit="a" * 40,
                )
            )
        )
        notified = self.run_cli(
            [
                sys.executable,
                str(TRANSITION_SPEC.origin),
                "apply-event",
                "example",
                "--source-revision",
                "source-1",
                "--event-file",
                str(event_path),
            ]
        )
        self.assertEqual(notified.returncode, 0)
        notified_output = json.loads(notified.stdout)
        self.assertEqual(notified_output["action"], "reserve_session")
        self.assertEqual(notified_output["details"]["task_id"], "B")

        resumed = self.run_cli(command)

        self.assertEqual(resumed.returncode, 0)
        resumed_output = json.loads(resumed.stdout)
        self.assertEqual(resumed_output["action"], "reserve_session")
        self.assertEqual(resumed_output["details"]["task_id"], "B")
        self.assertEqual(
            resumed_output["action_token"], notified_output["action_token"]
        )

    def test_cli_init_does_not_confirm_new_note_before_notification(self):
        self.create_tracked_session()
        tasks = self.root / "tasks.json"
        tasks.write_text(
            json.dumps(
                {
                    "tasks": [
                        {"id": "A", "dependencies": []},
                        {"id": "B", "dependencies": []},
                    ]
                }
            )
        )
        command = [
            sys.executable,
            str(TRANSITION_SPEC.origin),
            "init",
            "example",
            "--tasks",
            str(tasks),
            "--max-parallelism",
            "2",
            "--policy",
            "manual",
            "--source-revision",
            "source-1",
        ]
        first = self.run_cli(command)
        self.assertEqual(first.returncode, 0)
        first_output = json.loads(first.stdout)
        self.assertEqual(first_output["action"], "reserve_session")
        self.assertEqual(first_output["details"]["task_id"], "B")

        self.save_note("A", {})
        resumed = self.run_cli(command)
        self.assertEqual(resumed.returncode, 0)
        resumed_output = json.loads(resumed.stdout)
        self.assertEqual(resumed_output["action"], "reserve_session")
        self.assertEqual(resumed_output["details"]["task_id"], "B")
        self.assertEqual(resumed_output["action_token"], first_output["action_token"])

        state = transition.load_state(transition.transition_path("example"))
        event_path = self.root / "completion-notified-before-launch.json"
        event_path.write_text(
            json.dumps(
                self.event(
                    state,
                    "completion_notified",
                    notification=self.notification(),
                    observed_merge_commit="a" * 40,
                )
            )
        )
        notified = self.run_cli(
            [
                sys.executable,
                str(TRANSITION_SPEC.origin),
                "apply-event",
                "example",
                "--source-revision",
                "source-1",
                "--event-file",
                str(event_path),
            ]
        )
        self.assertEqual(notified.returncode, 0)
        notified_output = json.loads(notified.stdout)
        self.assertEqual(notified_output["action"], "reserve_session")
        self.assertEqual(notified_output["details"]["task_id"], "B")

    def test_cli_init_validates_old_external_state_before_cycle_change(self):
        self.create_tracked_session()
        state = transition.initial_state(
            "source-1",
            self.task_map([{"id": "A", "dependencies": []}]),
            [],
            1,
            "manual",
        )
        state["launch_history"] = [
            {
                "task_id": "A",
                "thread": {
                    "thread_id": "thread-a",
                    "host_id": "local",
                    "project_id": "saved-project",
                    "checkout": "/checkout/repository",
                },
            }
        ]
        transition.write_state(
            transition.transition_path("example"), transition.normalize_state(state)
        )
        tasks = self.root / "tasks.json"
        tasks.write_text(
            json.dumps(
                {
                    "tasks": [
                        {"id": "A", "dependencies": []},
                        {"id": "B", "dependencies": ["A"]},
                    ]
                }
            )
        )
        command = [
            sys.executable,
            str(TRANSITION_SPEC.origin),
            "init",
            "example",
            "--tasks",
            str(tasks),
            "--max-parallelism",
            "1",
            "--policy",
            "manual",
            "--source-revision",
            "source-2",
        ]
        sessions_path = storage.state_path("example")
        sessions = json.loads(sessions_path.read_text())
        sessions["tasks"]["A"]["child_thread_id"] = "contradictory-thread"
        sessions_path.write_text(json.dumps(sessions))
        changed = self.run_cli(command)

        self.assertEqual(changed.returncode, 2)
        self.assertEqual(
            json.loads(changed.stderr),
            {"error": "launch history does not match the session mapping"},
        )


if __name__ == "__main__":
    unittest.main()
