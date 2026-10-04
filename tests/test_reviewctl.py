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
        self.request = self.root / "request.json"
        self.data = {
            "identifier": "example",
            "worker": "Codex",
            "workerId": "worker",
            "checkout": str(self.root),
            "base": self.head,
            "head": self.head,
            "context": "日本語と {braces} と $values",
            "projectId": "project",
            "pushed": False,
            "pr": None,
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
    def test_rejects_stale_head_before_any_review(self):
        self.commit("test: changed head")
        with self.assertRaises(reviewctl.ReviewError):
            self.write_request()

    def test_rejects_symbolic_review_base(self):
        self.data["base"] = "HEAD"
        with self.assertRaises(reviewctl.ReviewError):
            self.write_request()

    def test_rejects_uncommitted_candidate(self):
        tracked = self.root / "tracked"
        tracked.write_text("initial")
        subprocess.run(["git", "-C", str(self.root), "add", "tracked"], check=True)
        with self.assertRaises(reviewctl.ReviewError):
            self.write_request()

    def test_context_survives_template_rendering(self):
        data = self.write_request()
        text = reviewctl.review_prompt(data, ROOT / "dot_codex/skills", self.request)
        self.assertIn(self.data["context"], text)
        self.assertIn(str(self.root), text)
        self.assertIn(self.head + "..." + self.head, text)


class ReviewSessionTest(ReviewFixture):
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
        self.assertFalse((self.root / "state.json").exists())
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

    def test_rerun_omits_unchanged_context_but_keeps_current_candidate(self):
        self.assertEqual(self.record()[0], 0)
        self.data.update(
            head=self.commit("test: review fixes"),
            pushed=True,
            pr="https://github.com/example/repo/pull/1",
        )
        self.write_request_file()
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        arguments = json.loads(out)["arguments"]
        self.assertEqual(arguments["threadId"], "reviewer")
        prompt = arguments["prompt"]
        self.assertNotIn(self.data["context"], prompt)
        for value in (
            self.data["workerId"],
            self.data["checkout"],
            self.data["pr"],
            self.head + "..." + self.data["head"],
            str(self.request.resolve()),
        ):
            self.assertIn(value, prompt)
        saved = json.loads(self.request.read_text())
        self.assertEqual(saved["context"], self.data["context"])
        for reference in ("reviewer.md", "reply-codex.md"):
            path = ROOT / "dot_codex/skills/task-review-cycle/references" / reference
            self.assertIn(str(path.resolve()), prompt)
            self.assertTrue(path.is_file())

    def test_changed_context_is_sent_until_accepted_candidate_is_recorded(self):
        self.assertEqual(self.record()[0], 0)
        self.data["context"] = "新しい要件と {braces} と $values"
        self.write_request_file()
        for _ in range(2):
            code, out, err = self.invoke("prepare", "--request", str(self.request))
            self.assertEqual(code, 0, err)
            self.assertIn(self.data["context"], json.loads(out)["arguments"]["prompt"])
        self.assertEqual(self.record()[0], 0)
        code, out, err = self.invoke("prepare", "--request", str(self.request))
        self.assertEqual(code, 0, err)
        self.assertNotIn(self.data["context"], json.loads(out)["arguments"]["prompt"])

    def test_full_context_restores_instructions_without_replacing_reviewer(self):
        for worker in ("Codex", "Claude"):
            with self.subTest(worker=worker):
                (self.root / "state.json").unlink(missing_ok=True)
                self.data["worker"] = worker
                self.write_request_file()
                code, out, err = self.invoke("prepare", "--request", str(self.request))
                self.assertEqual(code, 0, err)
                initial_prompt = json.loads(out)["arguments"]["prompt"]
                self.assertEqual(self.record()[0], 0)
                code, out, err = self.invoke(
                    "prepare", "--request", str(self.request), "--full-context"
                )
                self.assertEqual(code, 0, err)
                request = json.loads(out)
                self.assertEqual(request["tool"], "send_message_to_thread")
                self.assertEqual(request["arguments"]["threadId"], "reviewer")
                self.assertEqual(request["arguments"]["prompt"], initial_prompt)

    def test_record_rejects_provisional_self_and_different_reviewer(self):
        for reviewer in ("client-new-thread:queued", "worker"):
            with self.subTest(reviewer=reviewer):
                self.assertEqual(self.record(reviewer)[0], 1)
                self.assertFalse((self.root / "state.json").exists())
        self.assertEqual(self.record()[0], 0)
        self.assertEqual(self.record("different")[0], 1)
        state = json.loads((self.root / "state.json").read_text())
        self.assertEqual(state["reviewer"], "reviewer")

    def test_changed_session_identity_is_rejected_without_overwrite(self):
        self.assertEqual(self.record()[0], 0)
        before = (self.root / "state.json").read_text()
        original = self.data.copy()
        for key, value in (
            ("checkout", str(self.add_worktree())),
            ("workerId", "other-worker"),
            ("worker", "Claude"),
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
        before = (self.root / "state.json").read_text()
        self.run_git("checkout", "-qb", "upstream")
        base = self.commit("test: upstream")
        self.run_git("checkout", "-q", "--detach", self.head)
        head = self.commit("test: worker")
        self.data.update(base=base, head=head)
        self.write_request_file()
        code, out, err = self.invoke(
            "prepare", "--request", str(self.request), "--update-base"
        )
        self.assertEqual(code, 1)
        self.assertIn("ancestor", err)
        self.run_git("merge", "--no-edit", base)
        self.data["head"] = reviewctl.git(self.root, "rev-parse", "HEAD")
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
        self.assertIn(base + "..." + self.data["head"], prepared["arguments"]["prompt"])
        self.assertEqual((self.root / "state.json").read_text(), before)
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
        (self.request.parent / ".gitignore").write_text("*\n")
        self.write_request_file()
        self.assertEqual(reviewctl.git(checkout, "status", "--porcelain"), "")
        with mock.patch.object(reviewctl.Path, "cwd", return_value=checkout):
            code, out, err = self.invoke(
                "prepare", "--request", str(self.request), default_state=True
            )
            self.assertEqual(code, 0, err)
            self.assertFalse((checkout / ".reviewctl/state.json").exists())
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


if __name__ == "__main__":
    unittest.main()
