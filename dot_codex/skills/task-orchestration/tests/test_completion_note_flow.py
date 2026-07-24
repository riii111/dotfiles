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


class CompletionNoteWorker:
    def __init__(self, orchestration_id, task_id, note_path):
        self.orchestration_id = orchestration_id
        self.task_id = task_id
        self.note_path = note_path
        self.reads = 0
        self.writes = 0

    def complete(self, note):
        current = state.completion_note(self.orchestration_id, self.task_id)
        self.reads += 1
        if current["saved"]:
            return current

        self.note_path.write_text(json.dumps(note))
        state.record_completion_note(
            self.orchestration_id, self.task_id, self.note_path
        )
        self.writes += 1
        current = state.completion_note(self.orchestration_id, self.task_id)
        self.reads += 1
        if not current["saved"] or current["note"] != note:
            raise AssertionError("completion note was not saved")
        return current


class CompletionFlowDriver:
    def __init__(
        self, orchestration_id, tasks_path, maximum_parallelism, completed_ids=None
    ):
        self.orchestration_id = orchestration_id
        self.tasks_path = tasks_path
        self.maximum_parallelism = maximum_parallelism
        self.completed_ids = completed_ids or []
        self.resumed_tasks = set()
        self.resume_requests = []
        self.launches = []

    def run(self):
        result = state.plan_tasks(
            self.orchestration_id,
            state.load_tasks(self.tasks_path),
            self.completed_ids,
            self.maximum_parallelism,
        )
        for request in result["resume_completion_notes"]:
            if request["task_id"] not in self.resumed_tasks:
                self.resumed_tasks.add(request["task_id"])
                self.resume_requests.append(request)
        for task_id in result["selected"]:
            state.reserve_session(self.orchestration_id, task_id)
            self.launches.append(
                {
                    "task_id": task_id,
                    "dependency_completion_notes": result[
                        "dependency_completion_notes"
                    ].get(task_id, {}),
                }
            )
        return result


class CompletionNoteFlowTest(unittest.TestCase):
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
task_source = "linear://project"
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

    def worker(self, task_id):
        return CompletionNoteWorker(
            "example", task_id, self.root / f"completion-note-{task_id}.json"
        )

    def test_manual_flow_resumes_once_then_starts_direct_dependent_once(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ]
        )
        self.create_session_with_pull_request()
        worker = self.worker("A")
        driver = CompletionFlowDriver("example", tasks, 1, ["A"])

        driver.run()
        driver.run()

        self.assertEqual(
            [request["task_id"] for request in driver.resume_requests], ["A"]
        )
        self.assertEqual(driver.launches, [])

        worker.complete(
            {
                "risks": "Watch conversion errors after release.",
                "handoff": "Use ErrorKind::ExpiredToken.",
                "review_learnings": "Check retry paths with normal paths.",
                "technical_debt": "Unify duplicate conversions.",
            }
        )
        driver.run()
        driver.run()

        self.assertEqual(worker.reads, 2)
        self.assertEqual(worker.writes, 1)
        self.assertEqual(
            driver.launches,
            [
                {
                    "task_id": "B",
                    "dependency_completion_notes": {
                        "A": {
                            "risks": "Watch conversion errors after release.",
                            "handoff": "Use ErrorKind::ExpiredToken.",
                        }
                    },
                }
            ],
        )

    def test_auto_flow_skips_resume_and_worker_write_on_retry(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ]
        )
        self.create_session_with_pull_request()
        worker = self.worker("A")
        driver = CompletionFlowDriver("example", tasks, 1)

        worker.complete({"handoff": "Use this."})
        worker.complete({"handoff": "Ignored on retry."})
        driver.run()
        driver.run()

        self.assertEqual(worker.reads, 3)
        self.assertEqual(worker.writes, 1)
        self.assertEqual(driver.resume_requests, [])
        self.assertEqual(
            driver.launches,
            [
                {
                    "task_id": "B",
                    "dependency_completion_notes": {"A": {"handoff": "Use this."}},
                }
            ],
        )

    def test_empty_completion_note_is_terminal_for_manual_worker_retries(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ]
        )
        self.create_session_with_pull_request()
        worker = self.worker("A")
        driver = CompletionFlowDriver("example", tasks, 1, ["A"])

        driver.run()
        worker.complete({})
        worker.complete({"handoff": "Ignored on retry."})
        driver.run()

        self.assertEqual(worker.reads, 3)
        self.assertEqual(worker.writes, 1)
        self.assertEqual(
            driver.launches,
            [{"task_id": "B", "dependency_completion_notes": {}}],
        )

    def test_multiple_direct_dependencies_only_pass_handoff_and_risks(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": []},
                {"id": "C", "dependencies": ["A", "B"]},
            ]
        )
        self.create_session_with_pull_request("A", 42)
        self.create_session_with_pull_request("B", 43)
        self.worker("A").complete(
            {
                "handoff": "Use the A path.",
                "review_learnings": "Do not pass this on.",
            }
        )
        self.worker("B").complete(
            {
                "risks": "Watch the B rollout.",
                "technical_debt": "Do not pass this on.",
            }
        )
        driver = CompletionFlowDriver("example", tasks, 1)

        driver.run()

        self.assertEqual(
            driver.launches,
            [
                {
                    "task_id": "C",
                    "dependency_completion_notes": {
                        "A": {"handoff": "Use the A path."},
                        "B": {"risks": "Watch the B rollout."},
                    },
                }
            ],
        )

    def test_completion_note_save_failure_keeps_direct_dependents_blocked(self):
        tasks = self.tasks_file(
            [
                {"id": "A", "dependencies": []},
                {"id": "B", "dependencies": ["A"]},
            ]
        )
        self.create_session_with_pull_request()
        worker = self.worker("A")
        driver = CompletionFlowDriver("example", tasks, 1, ["A"])

        driver.run()
        with self.assertRaisesRegex(state.StateError, "non-empty string"):
            worker.complete({"handoff": " "})
        driver.run()

        self.assertEqual(worker.reads, 1)
        self.assertEqual(worker.writes, 0)
        self.assertEqual(
            [request["task_id"] for request in driver.resume_requests], ["A"]
        )
        self.assertEqual(driver.launches, [])

    def test_parent_orchestration_skill_stays_thin(self):
        orchestration_skill = (SKILL_ROOT / "SKILL.md").read_text()
        review_skill = (
            SKILL_ROOT.parent / "task-review-cycle" / "SKILL.md"
        ).read_text()

        self.assertLessEqual(len(orchestration_skill.splitlines()), 80)
        self.assertIn("`executor_skill`", orchestration_skill)
        for implementation_detail in (
            "operation_failed",
            "retryable",
            "reservation_released",
            "completion_waited",
            "thread_created",
            "thread_verified",
        ):
            self.assertNotIn(implementation_detail, orchestration_skill)
        for skill_name in ("task-completion-recovery", "task-session-launch"):
            self.assertTrue((SKILL_ROOT.parent / skill_name / "SKILL.md").is_file())
        self.assertIn("この子セッションへmergeを直接依頼", review_skill)
        self.assertIn("`completion-report`まで続け", review_skill)


if __name__ == "__main__":
    unittest.main()
