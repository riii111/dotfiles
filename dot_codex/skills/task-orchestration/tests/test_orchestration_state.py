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
        self.config_path = config_directory / "config.toml"
        self.config_path.write_text(
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

    def test_cli_reports_non_table_orchestrations_as_json_error(self):
        self.config_path.write_text('orchestrations = "invalid"\n')

        result = subprocess.run(
            [sys.executable, str(SPEC.origin), "context", "example"],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 2)
        self.assertEqual(
            json.loads(result.stderr),
            {"error": "configuration orchestrations must be a table"},
        )

    def test_records_a_pull_request_for_an_existing_session(self):
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

        self.assertEqual(result["version"], 1)
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

    def test_reservation_prevents_duplicate_selection(self):
        tasks = self.tasks_file([{"id": "A", "dependencies": []}])

        state.reserve_session("example", "A")
        result = state.plan("example", tasks, [], 1)

        self.assertEqual(result["selected"], [])
        self.assertEqual(result["launched_uncompleted"], ["A"])
        with self.assertRaisesRegex(
            state.StateError, "already has session creation state"
        ):
            state.reserve_session("example", "A")

    def test_only_a_reserved_creation_can_be_released(self):
        tasks = self.tasks_file([{"id": "A", "dependencies": []}])
        state.reserve_session("example", "A")

        released = state.release_reservation("example", "A")

        self.assertNotIn("A", released["tasks"])
        self.assertEqual(state.plan("example", tasks, [], 1)["selected"], ["A"])

    def test_record_pull_request_rejects_repository_and_number_changes(self):
        state.reserve_session("example", "A")
        state.record_session("example", "A", "thread-a")

        with self.assertRaisesRegex(state.StateError, "does not match"):
            state.record_pull_request("example", "A", "other/repository", 42)

        state.record_pull_request("example", "A", "owner/repository", 42)
        with self.assertRaisesRegex(state.StateError, "another pull request"):
            state.record_pull_request("example", "A", "owner/repository", 43)

    def test_record_pull_request_rejects_a_pull_request_used_by_another_task(self):
        state.reserve_session("example", "A")
        state.record_session("example", "A", "thread-a")
        state.reserve_session("example", "B")
        state.record_session("example", "B", "thread-b")
        state.record_pull_request("example", "A", "owner/repository", 42)

        with self.assertRaisesRegex(state.StateError, "already associated with task A"):
            state.record_pull_request("example", "B", "owner/repository", 42)

    def test_sessions_reject_duplicate_pull_request_associations(self):
        path = state.state_path("example")
        path.parent.mkdir(parents=True)
        pull_request = {"repository": "owner/repository", "number": 42}
        path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "parent_thread_id": "parent-thread",
                    "tasks": {
                        "A": {
                            "child_thread_id": "thread-a",
                            "pull_request": pull_request,
                        },
                        "B": {
                            "child_thread_id": "thread-b",
                            "pull_request": pull_request,
                        },
                    },
                }
            )
        )

        with self.assertRaisesRegex(state.StateError, "share a pull request"):
            state.load_sessions(path, "parent-thread", "owner/repository")

    def test_context_rejects_a_pull_request_from_another_repository(self):
        path = state.state_path("example")
        tasks = self.tasks_file([{"id": "A", "dependencies": []}])
        path.parent.mkdir(parents=True)
        path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "parent_thread_id": "parent-thread",
                    "tasks": {
                        "A": {
                            "child_thread_id": "thread-a",
                            "pull_request": {
                                "repository": "old/repository",
                                "number": 42,
                            },
                        }
                    },
                }
            )
        )

        result = subprocess.run(
            [sys.executable, str(SPEC.origin), "context", "example"],
            capture_output=True,
            check=False,
            text=True,
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("does not match the orchestration", result.stderr)
        with self.assertRaisesRegex(
            state.StateError, "does not match the orchestration"
        ):
            state.plan("example", tasks, [], 1)

    def test_sessions_and_merges_reject_boolean_versions(self):
        sessions_path = state.state_path("example")
        sessions_path.parent.mkdir(parents=True)
        sessions_path.write_text(
            json.dumps(
                {
                    "version": True,
                    "parent_thread_id": "parent-thread",
                    "tasks": {},
                }
            )
        )

        with self.assertRaisesRegex(state.StateError, "unsupported sessions version"):
            state.load_sessions(sessions_path, "parent-thread", "owner/repository")

        merges_path = state.merges_path("example")
        merges_path.write_text(json.dumps({"version": True, "pull_requests": {}}))
        with self.assertRaisesRegex(state.StateError, "unsupported merges version"):
            state.load_merges(
                merges_path,
                state.empty_sessions("parent-thread"),
                "owner/repository",
            )


if __name__ == "__main__":
    unittest.main()
