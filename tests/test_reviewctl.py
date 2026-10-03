import importlib.machinery
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
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
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(
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
                "commit",
                "-q",
                "--allow-empty",
                "-m",
                "test: initial",
            ],
            check=True,
        )
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

    def write_request(self):
        self.request.write_text(json.dumps(self.data))
        return reviewctl.candidate(self.request)


class ReviewCandidateTest(ReviewFixture):
    def test_rejects_stale_head_before_any_review(self):
        self.data["head"] = "f" * 40
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
        text = reviewctl.review_prompt(data, ROOT / "dot_codex/skills")
        self.assertIn(self.data["context"], text)
        self.assertIn(str(self.root), text)
        self.assertIn(self.head + "..." + self.head, text)


class ReviewSessionTest(ReviewFixture):
    def invoke(self, *arguments):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = reviewctl.main(
                [
                    "--state",
                    str(self.root / "state.json"),
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

    def test_record_rejects_provisional_self_and_different_reviewer(self):
        for reviewer in ("client-new-thread:queued", "worker"):
            with self.subTest(reviewer=reviewer):
                self.assertEqual(self.record(reviewer)[0], 1)
                self.assertFalse((self.root / "state.json").exists())
        self.assertEqual(self.record()[0], 0)
        self.assertEqual(self.record("different")[0], 1)
        state = json.loads((self.root / "state.json").read_text())
        self.assertEqual(state["reviewer"], "reviewer")

    def test_changed_session_base_or_worker_is_rejected_without_overwrite(self):
        self.assertEqual(self.record()[0], 0)
        before = (self.root / "state.json").read_text()
        original = self.data.copy()
        for key, value in (
            ("checkout", str(self.root.parent)),
            ("workerId", "other-worker"),
            ("worker", "Claude"),
            ("projectId", "other-project"),
        ):
            with self.subTest(key=key):
                self.data = {**original, key: value}
                self.write_request_file()
                self.assertEqual(
                    self.invoke("prepare", "--request", str(self.request))[0], 1
                )
                self.assertEqual((self.root / "state.json").read_text(), before)

    def write_request_file(self):
        self.request.write_text(json.dumps(self.data))


if __name__ == "__main__":
    unittest.main()
