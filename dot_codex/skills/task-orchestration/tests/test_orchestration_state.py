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
        state.record_session("example", "A", "thread-a")

        result = state.plan("example", tasks, [], 1)

        self.assertEqual(result["selected"], [])
        self.assertEqual(result["launched_uncompleted"], ["A"])
        self.assertEqual(result["available_slots"], 0)

    def test_plan_rejects_a_missing_dependency(self):
        tasks = self.tasks_file([{"id": "A", "dependencies": ["MISSING"]}])

        with self.assertRaisesRegex(state.StateError, "missing task MISSING"):
            state.plan("example", tasks, [], 1)

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

        self.assertEqual(result["version"], 2)
        self.assertEqual(
            result["tasks"]["A"]["pull_request"],
            {"repository": "owner/repository", "number": 42},
        )
        self.assertEqual(json.loads(sessions_path.read_text()), result)

    def test_record_session_is_idempotent_and_rejects_a_conflict(self):
        first = state.record_session("example", "A", "thread-a")
        second = state.record_session("example", "A", "thread-a")

        self.assertEqual(first, second)
        with self.assertRaisesRegex(state.StateError, "another thread"):
            state.record_session("example", "A", "thread-b")


if __name__ == "__main__":
    unittest.main()
