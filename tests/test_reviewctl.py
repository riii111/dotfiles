import importlib.machinery
import importlib.util
import json
import subprocess
import tempfile
import socket
import threading
import io
import os
from contextlib import contextmanager, redirect_stdout, redirect_stderr
from unittest import mock
import unittest
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

    def test_refuses_string_push_state(self):
        self.data["pushed"] = "false"
        with self.assertRaises(reviewctl.ReviewError):
            self.write_request()

    def test_context_survives_template_rendering(self):
        data = self.write_request()
        text = reviewctl.review_prompt(data, "worker-id", ROOT / "dot_codex/skills")
        self.assertIn(self.data["context"], text)
        self.assertIn(str(self.root), text)
        self.assertIn(self.head + "..." + self.head, text)

    def test_pending_write_blocks_a_second_write(self):
        state_path = self.root / "state.json"
        reviewctl.save_state(
            state_path,
            {
                "pending": True,
                "caller": "worker",
                "socket": "/tmp/socket",
                "candidate": {"base": self.head, "head": self.head},
            },
        )
        with self.assertRaises(reviewctl.ReviewError):
            reviewctl.read_state(state_path)

    def test_state_lock_prevents_concurrent_writers(self):
        state_path = self.root / "state.json"
        with reviewctl.locked_state(state_path):
            with self.assertRaises(reviewctl.ReviewError):
                with reviewctl.locked_state(state_path):
                    self.fail("second writer acquired the lock")


@contextmanager
def bridge(path, responses, requests):
    server = socket.socket(socket.AF_UNIX)
    server.bind(str(path))
    server.listen()
    server.settimeout(5)
    errors = []

    def run():
        try:
            for response in responses:
                connection, _ = server.accept()
                with connection, connection.makefile("rb") as stream:
                    request = json.loads(stream.readline())
                    requests.append(request)
                    if response is None:
                        continue
                    body = {"id": request["id"], **response}
                    connection.sendall((json.dumps(body) + "\n").encode())
        except Exception as error:
            errors.append(error)

    thread = threading.Thread(target=run)
    thread.start()
    try:
        yield
    finally:
        thread.join(6)
        server.close()
        if errors:
            raise errors[0]
        if thread.is_alive():
            raise AssertionError("fake bridge did not finish")


def result(data):
    return {"result": {"content": [], "structuredContent": data}}


class ReviewCliTest(ReviewFixture):
    def invoke(self, *arguments, environment=None):
        out, err = io.StringIO(), io.StringIO()
        with (
            mock.patch.dict(os.environ, environment or {}, clear=True),
            redirect_stdout(out),
            redirect_stderr(err),
        ):
            code = reviewctl.main(
                [
                    "--socket",
                    str(self.root / "bridge.sock"),
                    "--caller-thread-id",
                    "worker",
                    "--state",
                    str(self.root / "state.json"),
                    "--skills-root",
                    str(ROOT / "dot_codex/skills"),
                    *arguments,
                ]
            )
        return code, out.getvalue(), err.getvalue()

    def test_create_and_receive_review_over_socket(self):
        self.write_request()
        calls = []
        responses = [
            result({"threadId": "reviewer"}),
            result(
                {
                    "wake": {"reason": "turnCompleted"},
                    "polls": [{"thread": {"id": "reviewer"}, "cursor": "cursor-1"}],
                }
            ),
            result(
                {
                    "turns": [
                        {
                            "id": "review-turn",
                            "status": "completed",
                            "items": [
                                {
                                    "type": "agentMessage",
                                    "phase": "final_answer",
                                    "text": "LGTM: " + self.head,
                                }
                            ],
                        }
                    ]
                }
            ),
        ]
        with bridge(self.root / "bridge.sock", responses, calls):
            self.assertEqual(self.invoke("start", "--request", str(self.request))[0], 0)
            code, out, err = self.invoke("wait")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["status"], "review_available")
        self.assertEqual(calls[0]["arguments"]["model"], "gpt-6.1-sol")
        self.assertEqual(calls[0]["arguments"]["thinking"], "medium")
        self.assertEqual(calls[1]["arguments"]["targets"], [{"threadId": "reviewer"}])
        self.assertEqual(
            json.loads((self.root / "state.json").read_text())["cursor"], "cursor-1"
        )

    def test_lost_creation_response_does_not_create_twice(self):
        self.write_request()
        calls = []
        with bridge(self.root / "bridge.sock", [None], calls):
            self.assertEqual(self.invoke("start", "--request", str(self.request))[0], 1)
        self.assertTrue(json.loads((self.root / "state.json").read_text())["pending"])
        self.assertEqual(self.invoke("start", "--request", str(self.request))[0], 1)
        self.assertEqual(len(calls), 1)

    def test_known_refusal_allows_corrected_creation(self):
        self.write_request()
        calls = []
        with bridge(
            self.root / "bridge.sock",
            [
                {"error": {"code": "refused", "message": "bad model"}},
                result({"threadId": "reviewer"}),
            ],
            calls,
        ):
            self.assertEqual(self.invoke("start", "--request", str(self.request))[0], 1)
            self.assertFalse((self.root / "state.json").exists())
            self.assertEqual(self.invoke("start", "--request", str(self.request))[0], 0)

    def test_rerun_keeps_settings_and_rejects_previous_answer(self):
        self.write_request()
        reviewctl.save_state(
            self.root / "state.json",
            {
                "caller": "worker",
                "socket": str(self.root / "bridge.sock"),
                "reviewer": "reviewer",
                "candidate": self.data,
                "pending": False,
                "cursor": "cursor-old",
                "review": "old result",
            },
        )
        calls = []
        old = result(
            {
                "turns": [
                    {
                        "id": "previous",
                        "status": "completed",
                        "items": [
                            {
                                "type": "agentMessage",
                                "phase": "final_answer",
                                "text": "old result",
                            }
                        ],
                    }
                ]
            }
        )
        with bridge(
            self.root / "bridge.sock",
            [
                old,
                result({"threadId": "reviewer"}),
                result({"wake": {"reason": "turnCompleted"}}),
                old,
            ],
            calls,
        ):
            self.assertEqual(self.invoke("rerun", "--request", str(self.request))[0], 0)
            code, out, err = self.invoke("wait")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["status"], "pending")
        self.assertEqual(calls[1]["arguments"]["threadId"], "reviewer")
        self.assertNotIn("model", calls[1]["arguments"])
        self.assertNotIn("thinking", calls[1]["arguments"])
        self.assertEqual(
            calls[2]["arguments"]["targets"][0]["afterCursor"], "cursor-old"
        )

    def test_commentary_is_not_a_completed_review(self):
        self.write_request()
        reviewctl.save_state(
            self.root / "state.json",
            {
                "caller": "worker",
                "socket": str(self.root / "bridge.sock"),
                "reviewer": "reviewer",
                "candidate": self.data,
                "pending": False,
            },
        )
        calls = []
        with bridge(
            self.root / "bridge.sock",
            [
                result({"wake": {"reason": "turnCompleted"}}),
                result(
                    {
                        "turns": [
                            {
                                "id": "turn",
                                "status": "completed",
                                "items": [
                                    {
                                        "type": "agentMessage",
                                        "phase": "commentary",
                                        "text": "reviewing",
                                    }
                                ],
                            }
                        ]
                    }
                ),
            ],
            calls,
        ):
            code, out, err = self.invoke("wait")
        self.assertEqual(code, 0, err)
        self.assertEqual(json.loads(out)["status"], "pending")

    def test_wait_exposes_target_errors_and_keeps_timeouts_pending(self):
        self.write_request()
        reviewctl.save_state(
            self.root / "state.json",
            {
                "caller": "worker",
                "socket": str(self.root / "bridge.sock"),
                "reviewer": "reviewer",
                "candidate": self.data,
                "pending": False,
            },
        )
        error = {"threadId": "reviewer", "message": "No Codex thread found"}
        calls = []
        with bridge(
            self.root / "bridge.sock",
            [
                result({"timedOut": False, "polls": [], "errors": [error]}),
                result({"timedOut": True, "polls": [], "errors": []}),
            ],
            calls,
        ):
            code, out, err = self.invoke("wait")
            self.assertEqual(code, 0, err)
            self.assertEqual(json.loads(out)["status"], "needs_attention")
            self.assertEqual(json.loads(out)["errors"], [error])
            code, out, err = self.invoke("wait")
            self.assertEqual(code, 0, err)
            self.assertEqual(json.loads(out)["status"], "pending")
        self.assertEqual([call["tool"] for call in calls], ["wait_threads"] * 2)

    def test_claude_token_is_sent_but_not_saved(self):
        self.write_request()
        calls = []
        with bridge(
            self.root / "bridge.sock", [result({"threadId": "reviewer"})], calls
        ):
            code, out, err = self.invoke(
                "start",
                "--request",
                str(self.request),
                environment={
                    "HARNEXUS_THREAD_ID": "worker",
                    "HARNEXUS_LINK_TOKEN": "session-token",
                },
            )
        self.assertEqual(code, 0, err)
        self.assertEqual(calls[0]["token"], "session-token")
        self.assertNotIn("session-token", (self.root / "state.json").read_text())

    def test_rejected_rerun_restores_previous_candidate(self):
        self.write_request()
        state = {
            "caller": "worker",
            "socket": str(self.root / "bridge.sock"),
            "reviewer": "reviewer",
            "candidate": self.data,
            "pending": False,
            "review": "old result",
        }
        reviewctl.save_state(self.root / "state.json", state)
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
                "test: next",
            ],
            check=True,
        )
        self.data = {**self.data, "head": reviewctl.git(self.root, "rev-parse", "HEAD")}
        self.write_request()
        calls = []
        with bridge(
            self.root / "bridge.sock",
            [
                result({"turns": [{"id": "old"}]}),
                {"error": {"code": "not_sent", "message": "stopped"}},
            ],
            calls,
        ):
            self.assertEqual(self.invoke("rerun", "--request", str(self.request))[0], 1)
        self.assertEqual(json.loads((self.root / "state.json").read_text()), state)


if __name__ == "__main__":
    unittest.main()
