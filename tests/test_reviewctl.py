import importlib.machinery
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from unittest import mock
from contextlib import redirect_stdout, redirect_stderr
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader(
    "reviewctl", str(ROOT / "bin/executable_reviewctl")
)
spec = importlib.util.spec_from_loader(loader.name, loader)
reviewctl = importlib.util.module_from_spec(spec)
loader.exec_module(reviewctl)


class ReviewFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run_git("init", "-q")
        self.commit("test: initial")
        self.head = reviewctl.git(self.root, "rev-parse", "HEAD")
        self.run_git("branch", "base")
        self.request = self.root / "request.json"
        self.data = {
            "taskId": "example",
            "workerAI": "Codex",
            "workerChatId": "worker",
            "checkout": str(self.root),
            "baseBranch": "base",
            "documentRefs": [str(ROOT / "AGENTS.md"), "https://example.com/task/1"],
            "projectId": "project",
            "prUrl": None,
        }

    def run_git(self, *arguments):
        return subprocess.run(
            [
                "git",
                "-C",
                str(self.root),
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "-c",
                "commit.gpgsign=false",
                *arguments,
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def commit(self, message):
        self.run_git("commit", "--allow-empty", "-qm", message)
        return reviewctl.git(self.root, "rev-parse", "HEAD")

    def add_worktree(self):
        checkout = self.root / "other-checkout"
        self.run_git("worktree", "add", "--detach", "-q", str(checkout), self.head)
        return checkout

    def write_request(self):
        self.request.write_text(json.dumps(self.data))
        return reviewctl.candidate(self.request)


class ReviewCandidateTest(ReviewFixture):
    def test_rejects_old_free_text_and_manual_snapshot_fields(self):
        for key, value in (
            ("context", "copy all historical context"),
            ("pushed", True),
            ("head", self.head),
        ):
            with self.subTest(key=key):
                self.data[key] = value
                with self.assertRaises(reviewctl.ReviewError):
                    self.write_request()
                del self.data[key]

    def test_resolves_branch_and_current_head_without_manual_shas(self):
        head = self.commit("test: changed head")
        data = self.write_request()
        self.assertEqual(data["base"], self.head)
        self.assertEqual(data["head"], head)

    def test_rejects_revision_expression_as_base_branch(self):
        self.data["baseBranch"] = "HEAD~0"
        with self.assertRaises(reviewctl.ReviewError):
            self.write_request()

    def test_rejects_uncommitted_candidate(self):
        tracked = self.root / "tracked"
        tracked.write_text("initial")
        subprocess.run(["git", "-C", str(self.root), "add", "tracked"], check=True)
        with self.assertRaises(reviewctl.ReviewError):
            self.write_request()

    def test_references_and_fixed_range_survive_rendering(self):
        data = self.write_request()
        text = reviewctl.review_prompt(data, ROOT / "dot_codex/skills")
        for reference in self.data["documentRefs"]:
            self.assertIn(reference, text)
        self.assertIn(str(self.root), text)
        self.assertIn(self.head + "..." + self.head, text)


class ReviewSessionTest(ReviewFixture):
    def legacy_state(self, pending=False):
        data = {
            "identifier": "example",
            "worker": "Codex",
            "workerId": "worker",
            "projectId": "project",
            "checkout": str(self.root),
            "base": self.head,
            "head": self.head,
            "context": "old free text",
            "pushed": False,
            "pr": None,
        }
        state = {"reviewer": None if pending else "reviewer", "candidate": data}
        if pending:
            state["pending_create"] = True
        (self.root / "state.json").write_text(json.dumps(state))
        return data

    def test_legacy_confirmed_state_reuses_reviewer_after_schema_migration(self):
        self.legacy_state()
        self.write_request_file()
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["arguments"]["threadId"], "reviewer")
        self.assertNotIn("old free text", json.loads(out)["arguments"]["prompt"])
        self.assertEqual(self.record()[0], 0)
        self.assertEqual(
            json.loads((self.root / "state.json").read_text())["candidate"]["taskId"],
            "example",
        )

    def test_legacy_pending_requires_original_request_before_migration(self):
        old = self.legacy_state(pending=True)
        self.write_request_file()
        before = (self.root / "state.json").read_text()
        self.assertEqual(self.invoke("prepare", "--request", str(self.request))[0], 1)
        self.assertEqual(self.record()[0], 1)
        self.assertEqual((self.root / "state.json").read_text(), before)
        self.request.write_text(json.dumps(old))
        self.assertEqual(
            self.invoke(
                "record",
                "--request",
                str(self.request),
                "--reviewer-thread-id",
                "reviewer",
            )[0],
            0,
        )
        self.write_request_file()
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["arguments"]["threadId"], "reviewer")

    def test_initial_record_rejects_checkout_advanced_after_prepare(self):
        self.write_request_file()
        self.assertEqual(self.invoke("prepare", "--request", str(self.request))[0], 0)
        before = (self.root / "state.json").read_text()
        self.commit("test: changed before acceptance")
        self.assertEqual(self.record()[0], 1)
        self.assertEqual((self.root / "state.json").read_text(), before)

    def invoke(self, *arguments, default_state=False):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = reviewctl.main(
                [
                    *(
                        []
                        if default_state
                        else ["--state", str(self.root / "state.json")]
                    ),
                    "--skills-root",
                    str(ROOT / "dot_codex/skills"),
                    *arguments,
                ]
            )
        return code, out.getvalue(), err.getvalue()

    def record(self, reviewer="reviewer"):
        self.write_request()
        return self.invoke(
            "record",
            "--request",
            str(self.request),
            "--reviewer-thread-id",
            reviewer,
        )

    def test_prepare_has_no_saved_reviewer_until_record(self):
        self.write_request()
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        request = json.loads(out)
        self.assertEqual(request["tool"], "create_thread")
        self.assertEqual(
            request["arguments"]["target"]["environment"]["type"], "worktree"
        )
        self.assertEqual(request["arguments"]["model"], "gpt-6.1-sol")
        self.assertEqual(request["arguments"]["thinking"], "medium")
        pending = json.loads((self.root / "state.json").read_text())
        self.assertTrue(pending["pending_create"])
        self.assertIsNone(pending["reviewer"])
        self.assertEqual(pending["candidate"], self.write_request())
        self.assertEqual(self.record()[0], 0)
        code, out, err = self.invoke("state")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["reviewer"], "reviewer")
        self.assertEqual(json.loads(out)["candidate"]["head"], self.head)

    def test_rerun_keeps_reviewer_and_model_settings(self):
        self.assertEqual(self.record()[0], 0)
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        request = json.loads(out)
        self.assertEqual(request["tool"], "send_message_to_thread")
        self.assertEqual(request["arguments"]["threadId"], "reviewer")
        self.assertNotIn("model", request["arguments"])
        self.assertNotIn("thinking", request["arguments"])
        code, out, err = self.invoke(
            "prepare", "--request", str(self.request), "--thinking", "high"
        )
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["arguments"]["thinking"], "high")

    def test_rerun_reuses_reviewer_with_current_head_and_document_references(self):
        self.assertEqual(self.record()[0], 0)
        head = self.commit("test: review fixes")
        self.data["prUrl"] = "https://github.com/example/repo/pull/1"
        self.write_request_file()
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        arguments = json.loads(out)["arguments"]
        self.assertEqual(arguments["threadId"], "reviewer")
        prompt = arguments["prompt"]
        for value in (
            *self.data["documentRefs"],
            self.data["workerChatId"],
            self.data["checkout"],
            self.data["prUrl"],
            self.head + "..." + head,
        ):
            self.assertIn(value, prompt)

    def test_rereview_record_rejects_head_changed_after_prepare(self):
        self.assertEqual(self.record()[0], 0)
        self.commit("test: first fix")
        self.assertEqual(self.invoke("prepare", "--request", str(self.request))[0], 0)
        before = (self.root / "state.json").read_text()
        self.commit("test: change while sending")
        self.assertEqual(self.record()[0], 1)
        self.assertEqual((self.root / "state.json").read_text(), before)

    def test_upstream_branch_advancement_keeps_recorded_review_base(self):
        self.assertEqual(self.record()[0], 0)
        self.run_git("branch", "-f", "base", self.commit("test: upstream advances"))
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        self.assertIn(self.head + "...", json.loads(out)["arguments"]["prompt"])
        self.assertEqual(
            json.loads((self.root / "state.json").read_text())["prepared"]["base"],
            self.head,
        )

    def test_record_rejects_provisional_self_and_different_reviewer(self):
        for reviewer in (
            "client-new-thread:queued",
            "worker",
            "reviewer ",
            " reviewer",
        ):
            with self.subTest(reviewer=reviewer):
                self.assertEqual(self.record(reviewer)[0], 1)
                self.assertFalse((self.root / "state.json").exists())
        self.assertEqual(self.record()[0], 0)
        self.assertEqual(self.record("different")[0], 1)
        state = json.loads((self.root / "state.json").read_text())
        self.assertEqual(state["reviewer"], "reviewer")

    def test_worker_id_whitespace_cannot_bypass_self_review_rejection(self):
        for worker_id in ("worker ", " worker"):
            with self.subTest(worker_id=worker_id):
                self.data["workerChatId"] = worker_id
                self.write_request_file()
                self.assertEqual(
                    self.invoke(
                        "record",
                        "--request",
                        str(self.request),
                        "--reviewer-thread-id",
                        "worker",
                    )[0],
                    1,
                )
                self.assertFalse((self.root / "state.json").exists())

    def test_changed_session_identity_is_rejected_without_overwrite(self):
        self.assertEqual(self.record()[0], 0)
        before = (self.root / "state.json").read_text()
        original = self.data.copy()
        for key, value in (
            ("checkout", str(self.add_worktree())),
            ("workerChatId", "other-worker"),
            ("workerAI", "Claude"),
            ("projectId", "other-project"),
        ):
            with self.subTest(key=key):
                self.data = {**original, key: value}
                self.write_request_file()
                code, out, err = self.invoke("prepare", "--request", str(self.request))
                self.assertEqual(code, 1)
                self.assertIn(f"original {key}", err)
                self.assertEqual((self.root / "state.json").read_text(), before)

    def test_base_update_requires_integration_and_keeps_reviewer(self):
        self.assertEqual(self.record()[0], 0)
        self.run_git("checkout", "-qb", "upstream")
        base = self.commit("test: upstream")
        self.run_git("checkout", "-q", "--detach", self.head)
        head = self.commit("test: worker")
        self.data["baseBranch"] = "upstream"
        self.write_request_file()
        code, out, err = self.invoke(
            "prepare", "--request", str(self.request), "--update-base"
        )
        self.assertEqual(code, 1)
        self.assertIn("ancestor", err)
        self.run_git("merge", "--no-edit", base)
        head = reviewctl.git(self.root, "rev-parse", "HEAD")
        self.write_request_file()
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 1)
        self.assertIn("--update-base", err)
        code, out, err = self.invoke(
            "prepare", "--request", str(self.request), "--update-base"
        )
        self.assertEqual(code, 0, err)
        prepared = json.loads(out)
        self.assertEqual(prepared["arguments"]["threadId"], "reviewer")
        self.assertIn(base + "..." + head, prepared["arguments"]["prompt"])
        self.assertEqual(
            json.loads((self.root / "state.json").read_text())["candidate"]["base"],
            self.head,
        )
        self.assertEqual(self.record()[0], 1)
        code, out, err = self.invoke(
            "record",
            "--request",
            str(self.request),
            "--reviewer-thread-id",
            "reviewer",
            "--update-base",
        )
        self.assertEqual(code, 0, err)
        recorded = json.loads(out)
        self.assertEqual(recorded["reviewer"], "reviewer")
        self.assertEqual(recorded["candidate"]["base"], base)

    def test_default_state_is_local_and_ignored_in_linked_worktree(self):
        checkout = self.add_worktree()
        self.data["checkout"] = str(checkout)
        self.request = checkout / ".reviewctl/request.json"
        self.request.parent.mkdir()
        self.write_request_file()
        with mock.patch.object(reviewctl.Path, "cwd", return_value=checkout):
            code, out, err = self.invoke(
                "prepare", "--request", str(self.request), default_state=True
            )
            self.assertEqual(code, 0, err)
            pending = json.loads((checkout / ".reviewctl/state.json").read_text())
            self.assertTrue(pending["pending_create"])
            self.assertEqual(reviewctl.git(checkout, "status", "--porcelain"), "")
            code, out, err = self.invoke(
                "record",
                "--request",
                str(self.request),
                "--reviewer-thread-id",
                "reviewer",
                default_state=True,
            )
            self.assertEqual(code, 0, err)
            self.assertTrue((checkout / ".reviewctl/state.json").is_file())
            code, out, err = self.invoke("state", default_state=True)
            self.assertEqual(code, 0, err)
            self.assertEqual(json.loads(out)["reviewer"], "reviewer")
        self.assertEqual(reviewctl.git(checkout, "status", "--porcelain"), "")
        self.assertFalse((self.root / ".reviewctl").exists())

    def write_request_file(self):
        self.request.write_text(json.dumps(self.data))

    def test_pending_survives_restart_and_blocks_duplicate_creation(self):
        self.write_request()
        command = [
            str(ROOT / "bin/executable_reviewctl"),
            "--state",
            str(self.root / "state.json"),
            "--skills-root",
            str(ROOT / "dot_codex/skills"),
            "prepare",
            "--request",
            str(self.request),
        ]
        first = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(json.loads(first.stdout)["tool"], "create_thread")
        before = (self.root / "state.json").read_text()
        second = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(second.returncode, 1)
        self.assertEqual(second.stdout, "")
        self.assertIn("pending", second.stderr)
        self.assertEqual((self.root / "state.json").read_text(), before)
        self.assertEqual(self.record()[0], 0)
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["tool"], "send_message_to_thread")
        self.assertEqual(json.loads(out)["arguments"]["threadId"], "reviewer")

    def test_concurrent_initial_prepares_emit_one_creation(self):
        self.write_request()
        command = [
            str(ROOT / "bin/executable_reviewctl"),
            "--state",
            str(self.root / "state.json"),
            "--skills-root",
            str(ROOT / "dot_codex/skills"),
            "prepare",
            "--request",
            str(self.request),
        ]
        processes = [
            subprocess.Popen(
                command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            for _ in range(2)
        ]
        results = [
            (*process.communicate(), process.returncode) for process in processes
        ]
        self.assertEqual(sorted(code for _, _, code in results), [0, 1])
        emitted = [json.loads(out) for out, _, code in results if code == 0]
        self.assertEqual([item["tool"] for item in emitted], ["create_thread"])

    def test_pending_record_rejects_changed_candidate_without_overwrite(self):
        self.write_request()
        self.assertEqual(self.invoke("prepare", "--request", str(self.request))[0], 0)
        before = (self.root / "state.json").read_text()
        self.data["documentRefs"].append("https://example.com/changed")
        self.assertEqual(self.record()[0], 1)
        self.assertEqual((self.root / "state.json").read_text(), before)

    def test_only_confirmed_unsent_creation_can_be_released(self):
        self.write_request()
        self.assertEqual(self.invoke("prepare", "--request", str(self.request))[0], 0)
        with self.assertRaises(SystemExit):
            self.invoke("reset-pending")
        self.assertTrue((self.root / "state.json").exists())
        code, out, err = self.invoke("reset-pending", "--not-sent")
        self.assertEqual(code, 0, err)
        self.assertFalse((self.root / "state.json").exists())
        self.assertEqual(self.invoke("prepare", "--request", str(self.request))[0], 0)
        self.assertEqual(self.record()[0], 0)
        before = (self.root / "state.json").read_text()
        self.assertEqual(self.invoke("reset-pending", "--not-sent")[0], 1)
        self.assertEqual((self.root / "state.json").read_text(), before)


if __name__ == "__main__":
    unittest.main()
