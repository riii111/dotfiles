import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SKILL_ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "orchestration_state", SKILL_ROOT / "scripts" / "orchestration_state.py"
)
state = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(state)


class OrchestrationStateTest(unittest.TestCase):
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
task_source = "linear://project"
""".lstrip()
        )
        self.environment = patch.dict(
            os.environ,
            {
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
            },
        )
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.temporary.cleanup()

    def tasks_file(self, tasks):
        path = self.root / "tasks.json"
        path.write_text(json.dumps({"tasks": tasks}))
        return path

    def create_session_with_pull_request(self, task_id="A", number=42):
        state.reserve_session("example", task_id)
        state.record_session("example", task_id, f"thread-{task_id.lower()}")
        state.record_pull_request("example", task_id, "owner/repository", number)

    def write_merges(self, pull_requests):
        path = state.merges_path("example")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"version": 1, "pull_requests": pull_requests}))
        return path

    def test_plan_selects_independent_tasks_then_their_dependent(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": []},
                {"id": "C", "dependencies": ["A", "B"]},
            ]
        )

        first = state.plan("example", tasks, [], 2)
        next_plan = state.plan("example", tasks, ["A", "B"], 2)

        self.assertEqual(first["selected"], ["A", "B"])
        self.assertEqual(first["waiting_dependencies"], {"C": ["A", "B"]})
        self.assertEqual(next_plan["selected"], ["C"])

    def test_plan_counts_launched_uncompleted_tasks_against_capacity(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": []},
            ]
        )
        state.reserve_session("example", "A")
        state.record_session("example", "A", "thread-a")

        result = state.plan("example", tasks, [], 1)

        self.assertEqual(result["selected"], [])
        self.assertEqual(result["launched_uncompleted"], ["A"])
        self.assertEqual(result["available_slots"], 0)

    def test_plan_rejects_a_missing_dependency(self):
        tasks = self.tasks_file([{"id": "A", "dependencies": ["MISSING"]}])

        with self.assertRaisesRegex(state.StateError, "missing task MISSING"):
            state.plan("example", tasks, [], 1)

    def test_plan_rejects_a_dependency_cycle(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": ["B"]},
                {"id": "B", "dependencies": ["A"]},
            ]
        )

        with self.assertRaisesRegex(state.StateError, "dependency cycle"):
            state.plan("example", tasks, [], 1)

    def test_plan_rejects_unknown_completed_and_launched_tasks(self):
        tasks = self.tasks_file([{"id": "A", "dependencies": []}])

        with self.assertRaisesRegex(
            state.StateError, "absent from the current task source"
        ):
            state.plan("example", tasks, ["UNKNOWN"], 1)

        state.reserve_session("example", "UNKNOWN")
        with self.assertRaisesRegex(
            state.StateError, "absent from the current task source"
        ):
            state.plan("example", tasks, [], 1)

    def test_plan_uses_validated_merge_records_as_completed_tasks(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ]
        )
        self.create_session_with_pull_request()
        self.write_merges(
            {
                "42": {
                    "task_id": "A",
                    "merge_commit": "abc123",
                    "parent_notification": "pending",
                    "local_notification": "sent",
                }
            }
        )

        result = state.plan("example", tasks, [], 1)

        self.assertEqual(result["completed_from_merges"], ["A"])
        self.assertEqual(result["selected"], ["B"])

    def test_context_rejects_invalid_merge_notification_state(self):
        self.create_session_with_pull_request()
        path = self.write_merges(
            {
                "42": {
                    "task_id": "A",
                    "merge_commit": "abc123",
                    "parent_notification": "unknown",
                    "local_notification": "sent",
                }
            }
        )
        sessions = state.load_sessions(state.state_path("example"), "parent-thread")

        with self.assertRaisesRegex(state.StateError, "invalid parent notification"):
            state.load_merges(path, sessions, "owner/repository")

    def test_records_session_and_pull_request_and_upgrades_version_one(self):
        sessions_path = state.state_path("example")
        sessions_path.parent.mkdir(parents=True)
        sessions_path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "parent_thread_id": "parent-thread",
                    "tasks": {"A": {"child_thread_id": "thread-a"}},
                }
            )
        )

        result = state.record_pull_request("example", "A", "owner/repository", 42)

        self.assertEqual(result["version"], 3)
        self.assertEqual(
            result["tasks"]["A"]["pull_request"],
            {"repository": "owner/repository", "number": 42},
        )
        self.assertEqual(json.loads(sessions_path.read_text()), result)

    def test_record_session_is_idempotent_and_rejects_a_conflict(self):
        state.reserve_session("example", "A")
        first = state.record_session("example", "A", "thread-a")
        second = state.record_session("example", "A", "thread-a")

        self.assertEqual(first, second)
        with self.assertRaisesRegex(state.StateError, "another thread"):
            state.record_session("example", "A", "thread-b")

    def test_reservation_and_pending_creation_prevent_duplicate_selection(self):
        tasks = self.tasks_file([{"id": "A", "dependencies": []}])

        state.reserve_session("example", "A")
        reserved = state.plan("example", tasks, [], 1)
        state.record_pending("example", "A", "client-a")
        pending = state.plan("example", tasks, [], 1)

        self.assertEqual(reserved["selected"], [])
        self.assertEqual(pending["selected"], [])
        self.assertEqual(pending["launched_uncompleted"], ["A"])
        with self.assertRaisesRegex(
            state.StateError, "already has session creation state"
        ):
            state.reserve_session("example", "A")

    def test_record_pull_request_rejects_repository_and_number_changes(self):
        state.reserve_session("example", "A")
        state.record_session("example", "A", "thread-a")

        with self.assertRaisesRegex(state.StateError, "does not match"):
            state.record_pull_request("example", "A", "other/repository", 42)

        state.record_pull_request("example", "A", "owner/repository", 42)
        with self.assertRaisesRegex(state.StateError, "another pull request"):
            state.record_pull_request("example", "A", "owner/repository", 43)


if __name__ == "__main__":
    unittest.main()
