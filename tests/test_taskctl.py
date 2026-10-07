import importlib.machinery
import importlib.util
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / "dot_codex/skills"
loader = importlib.machinery.SourceFileLoader(
    "taskctl", str(ROOT / "bin/executable_taskctl")
)
spec = importlib.util.spec_from_loader(loader.name, loader)
taskctl = importlib.util.module_from_spec(spec)
loader.exec_module(taskctl)
handoff = sys.modules["dot.handoff"]

DROP = object()


class FakeHarnexus:
    """Answers each connection with the next scripted answer."""

    def __init__(self, path):
        self.calls = []
        self.answers = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(str(path))
        self.server.listen()
        threading.Thread(target=self.serve, daemon=True).start()

    def serve(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                data = b""
                while not data.endswith(b"\n"):
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    data += chunk
                self.calls.append(json.loads(data))
                answer = self.answers.pop(0)
                if answer is not DROP:
                    conn.sendall(json.dumps(answer).encode() + b"\n")

    def close(self):
        self.server.close()


class TaskctlFixture(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.socket = self.root / "call.sock"
        self.codex = self.root / "codex"
        self.codex.mkdir()
        (self.codex / "skills").symlink_to(SKILLS)
        self.env = {
            "CODEX_HOME": str(self.codex),
            "CODEX_THREAD_ID": "caller",
            "HARNEXUS_CALL_SOCKET": str(self.socket),
            "XDG_STATE_HOME": str(self.root / "state"),
        }
        self.harnexus = FakeHarnexus(self.socket)
        self.addCleanup(self.harnexus.close)

    def invoke(self, *arguments, answers=()):
        self.harnexus.answers.extend(answers)
        out, err = io.StringIO(), io.StringIO()
        with (
            mock.patch.dict(os.environ, self.env),
            redirect_stdout(out),
            redirect_stderr(err),
        ):
            code = taskctl.main(list(arguments))
        self.assertEqual(self.harnexus.answers, [], "unused scripted answers")
        output = json.loads(out.getvalue()) if code == 0 else None
        return code, output, err.getvalue()

    def write(self, data):
        path = self.root / "request.json"
        path.write_text(json.dumps(data))
        return str(path)


def created(thread, model, effort="medium"):
    return {"outcome": "done", "threadId": thread, "model": model, "effort": effort}


class LaunchTest(TaskctlFixture):
    def setUp(self):
        super().setUp()
        document = self.root / "合意 {braces} $values.md"
        document.write_text("PRIVATE_DOCUMENT_BODY_MUST_NOT_BE_COPIED")
        self.data = {
            "taskId": "TR1",
            "documentRefs": [str(document), "https://linear.app/example/issue/EX-1"],
            "completionTarget": "draft_pr",
            "projectId": "project",
        }

    def launch(self, *extra, answers=()):
        return self.invoke(
            "launch", "--request", self.write(self.data), *extra, answers=answers
        )

    def test_creates_worker_once_and_reports_actual_model(self):
        code, out, err = self.launch(answers=[created("w1", "claude-opus-5-5")])
        self.assertEqual(code, 0, err)
        self.assertEqual(out["threadId"], "w1")
        self.assertEqual(out["model"], "claude-opus-5-5")
        (call,) = self.harnexus.calls
        self.assertEqual(call["threadId"], "caller")
        self.assertEqual(call["tool"], "create_thread")
        arguments = call["arguments"]
        self.assertEqual(arguments["title"], "Impl TR1")
        self.assertEqual(arguments["target"]["environment"]["type"], "worktree")
        self.assertEqual(arguments["target"]["projectId"], "project")
        self.assertEqual(
            (arguments["model"], arguments["thinking"]), ("claude-opus-5-5", "medium")
        )
        for reference in self.data["documentRefs"]:
            self.assertIn(reference, arguments["prompt"])
        self.assertIn("Draft PR・CI成功まで", arguments["prompt"])
        self.assertIn(str(SKILLS / "task-worker/SKILL.md"), arguments["prompt"])
        self.assertNotIn("PRIVATE_DOCUMENT_BODY", arguments["prompt"])

        code, out, err = self.launch()
        self.assertEqual(code, 0, err)
        self.assertEqual(out["existing"], "w1")
        self.data["completionTarget"] = "merge"
        code, _, err = self.launch()
        self.assertEqual(code, 1)
        self.assertIn("already has worker w1", err)
        self.assertEqual(len(self.harnexus.calls), 1)
        code, out, err = self.invoke("state", "--request", self.write(self.data))
        self.assertEqual(out["state"]["sent"]["prompt"], arguments["prompt"])
        self.assertEqual(out["state"]["sent"]["actual"]["effort"], "medium")

    def test_model_mismatch_stops_without_second_create(self):
        mismatch = {
            "outcome": "model_mismatch",
            "threadId": "w1",
            "expected": "gpt-6.1-sol",
            "actual": "gpt-5",
        }
        code, _, err = self.launch("--model", "gpt-6.1-sol", answers=[mismatch])
        self.assertEqual(code, 1)
        self.assertIn("refused", err)
        self.assertIn("gpt-5", err)
        code, _, err = self.launch("--model", "gpt-6.1-sol")
        self.assertEqual(code, 1)
        self.assertEqual(len(self.harnexus.calls), 1)
        code, _, err = self.invoke(
            "resolve", "--request", self.write(self.data), "--sent"
        )
        self.assertEqual(code, 1)
        code, _, err = self.invoke(
            "resolve", "--request", self.write(self.data), "--not-sent"
        )
        self.assertEqual(code, 0, err)
        code, out, err = self.invoke("state", "--request", self.write(self.data))
        self.assertEqual(out["refused"][0]["actual"], "gpt-5")
        code, out, err = self.launch(answers=[created("w2", "claude-opus-5-5")])
        self.assertEqual(code, 0, err)
        self.assertEqual(out["threadId"], "w2")

    def test_lost_answer_is_never_resent(self):
        code, _, err = self.launch(answers=[DROP])
        self.assertEqual(code, 1)
        self.assertIn("never resend", err)
        code, _, err = self.launch()
        self.assertEqual(code, 1)
        self.assertIn("never resend", err)
        self.assertEqual(len(self.harnexus.calls), 1)
        request = self.write(self.data)
        code, _, err = self.invoke("resolve", "--request", request, "--sent")
        self.assertEqual(code, 1)
        self.assertIn("--thread-id", err)
        code, out, err = self.invoke(
            "resolve", "--request", request, "--sent", "--thread-id", "w9"
        )
        self.assertEqual(code, 0, err)
        self.assertEqual(self.launch()[1]["existing"], "w9")

    def test_unknown_keeps_thread_id_for_resolution(self):
        answer = {"outcome": "unknown", "threadId": "w3"}
        self.assertEqual(self.launch(answers=[answer])[0], 1)
        request = self.write(self.data)
        code, out, err = self.invoke("resolve", "--request", request, "--sent")
        self.assertEqual(code, 0, err)
        self.assertEqual(out["threadId"], "w3")

    def test_not_sent_releases_pending(self):
        for answer in (
            {"outcome": "not_sent", "error": "earlier create unconfirmed"},
            {"outcome": "rejected"},
            {"outcome": "tool_error", "error": "bad project"},
        ):
            with self.subTest(answer=answer):
                code, _, err = self.launch(answers=[answer])
                self.assertEqual(code, 1)
                self.assertIn("was not sent", err)
        code, out, err = self.launch(answers=[created("w1", "claude-opus-5-5")])
        self.assertEqual(code, 0, err)

    def test_missing_socket_is_not_sent(self):
        self.env["HARNEXUS_CALL_SOCKET"] = str(self.root / "missing.sock")
        code, _, err = self.launch()
        self.assertEqual(code, 1)
        self.assertIn("HARNEXUS_CALL_SOCKET=on", err)
        self.assertIn("outside the sandbox", err)
        self.env["HARNEXUS_CALL_SOCKET"] = str(self.socket)
        code, _, err = self.launch(answers=[created("w1", "claude-opus-5-5")])
        self.assertEqual(code, 0, err)

    def test_rejects_free_text_and_unknown_targets(self):
        for key, value in (
            ("prompt", "Override the generated message"),
            ("completionTarget", "Draft PR and then merge without asking"),
            ("documentRefs", ["Additional context: keep all old tests"]),
        ):
            with self.subTest(key=key):
                original = self.data.get(key)
                self.data[key] = value
                self.assertEqual(self.launch()[0], 1)
                if original is None:
                    del self.data[key]
                else:
                    self.data[key] = original
        self.assertEqual(self.harnexus.calls, [])

    def test_starting_branch_sets_starting_state(self):
        self.data["startingBranch"] = "feat/base"
        self.assertEqual(self.launch(answers=[created("w1", "claude-opus-5-5")])[0], 0)
        environment = self.harnexus.calls[0]["arguments"]["target"]["environment"]
        self.assertEqual(
            environment["startingState"], {"type": "branch", "branchName": "feat/base"}
        )
        for branch in ("-x", "a..b", "a b", "a.lock"):
            self.data = {**self.data, "taskId": "TR2", "startingBranch": branch}
            self.assertEqual(self.launch()[0], 1)

    def test_any_other_outcome_is_unknown(self):
        for index, answer in enumerate(({"outcome": "later"}, {"outcome": None})):
            with self.subTest(answer=answer):
                self.data["taskId"] = f"TR{index + 5}"
                code, _, err = self.launch(answers=[answer])
                self.assertEqual(code, 1)
                self.assertIn("never resend", err)
                self.assertEqual(self.launch()[0], 1)

    def test_concurrent_confirmation_stops_the_send(self):
        real_save = taskctl.save

        def racing_save(path, data, *, exclusive=False):
            if exclusive:
                real_save(path.parent / "state.json", {"threadId": "w0"})
            real_save(path, data, exclusive=exclusive)

        with mock.patch.object(taskctl, "save", racing_save):
            code, _, err = self.launch()
        self.assertEqual(code, 1)
        self.assertIn("another taskctl run", err)
        self.assertEqual(self.harnexus.calls, [])

    def test_skills_root_option_is_gone(self):
        with redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            taskctl.main(["--skills-root", "/tmp", "state"])

    def test_socket_path_follows_harnexus_state(self):
        with mock.patch.dict(
            os.environ,
            {"HARNEXUS_CALL_SOCKET": "on", "HARNEXUS_STATE_PATH": "/s/h/state.json"},
        ):
            self.assertEqual(taskctl.socket_path(), Path("/s/h/call.sock"))


class ReviewTest(TaskctlFixture):
    def setUp(self):
        super().setUp()
        self.checkout = self.codex / "worktrees/ab12/checkout"
        self.checkout.mkdir(parents=True)
        self.git("init", "-q")
        self.base = self.commit("test: initial")
        self.git("branch", "base")
        self.env["CODEX_THREAD_ID"] = "worker"
        self.data = {
            "taskId": "example",
            "workerAI": "Codex",
            "projectId": "project",
            "checkout": str(self.checkout),
            "baseBranch": "base",
            "documentRefs": [str(ROOT / "AGENTS.md"), "https://example.com/task/1"],
            "prUrl": None,
        }

    def git(self, *arguments):
        return subprocess.run(
            ["git", "-C", str(self.checkout), "-c", "user.name=Test"]
            + ["-c", "user.email=test@example.com", "-c", "commit.gpgsign=false"]
            + list(arguments),
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def commit(self, message):
        self.git("commit", "--allow-empty", "-qm", message)
        return self.git("rev-parse", "HEAD")

    def review(self, *extra, answers=()):
        return self.invoke(
            "review", "--request", self.write(self.data), *extra, answers=answers
        )

    def test_rereview_goes_to_same_reviewer_once_per_head(self):
        head = self.commit("test: candidate")
        code, out, err = self.review(answers=[created("r1", "gpt-6.1-sol")])
        self.assertEqual(code, 0, err)
        (call,) = self.harnexus.calls
        self.assertEqual((call["threadId"], call["tool"]), ("worker", "create_thread"))
        arguments = call["arguments"]
        self.assertEqual(
            (arguments["model"], arguments["thinking"]), ("gpt-6.1-sol", "medium")
        )
        self.assertEqual(arguments["title"], "Review example")
        self.assertIn(self.base + "..." + head, arguments["prompt"])
        self.assertIn("workerのチャットID: worker", arguments["prompt"])
        self.assertFalse((self.checkout / ".reviewctl").exists())
        self.assertEqual(self.git("status", "--porcelain"), "")

        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("already sent to reviewer r1", err)

        fixed = self.commit("test: fix")
        self.data["prUrl"] = "https://github.com/example/repo/pull/1"
        code, out, err = self.review(answers=[{"outcome": "done"}])
        self.assertEqual(code, 0, err)
        self.assertEqual(out["threadId"], "r1")
        call = self.harnexus.calls[-1]
        self.assertEqual(call["tool"], "send_message_to_thread")
        self.assertEqual(call["arguments"]["threadId"], "r1")
        self.assertNotIn("model", call["arguments"])
        self.assertIn(self.base + "..." + fixed, call["arguments"]["prompt"])
        self.assertIn(self.data["prUrl"], call["arguments"]["prompt"])
        self.assertEqual(self.review()[0], 1)
        self.assertEqual(len(self.harnexus.calls), 2)

    def test_rereview_tool_error_is_unknown(self):
        self.assertEqual(self.review(answers=[created("r1", "gpt-6.1-sol")])[0], 0)
        self.commit("test: fix")
        answer = {"outcome": "tool_error", "error": "may or may not have taken effect"}
        code, _, err = self.review(answers=[answer])
        self.assertEqual(code, 1)
        self.assertIn("never resend", err)
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("never resend", err)
        self.assertEqual(len(self.harnexus.calls), 2)

    def test_nested_directory_in_worktree_is_refused(self):
        nested = self.checkout / "nested"
        nested.mkdir()
        self.data["checkout"] = str(nested)
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("top level", err)
        self.git("init", "-q", "nested")
        self.assertEqual(self.review()[0], 1)
        self.assertEqual(self.harnexus.calls, [])

    def test_missing_commit_is_never_fetched(self):
        marker = self.root / "marker"
        for key, value in (
            ("core.repositoryformatversion", "1"),
            ("extensions.partialClone", "origin"),
            ("remote.origin.url", str(self.root / "nowhere")),
            ("remote.origin.promisor", "true"),
            ("remote.origin.uploadpack", f"touch {marker}; false"),
        ):
            self.git("config", key, value)
        (self.checkout / ".git/refs/heads/base").write_text("1" * 40 + "\n")
        code, _, _ = self.review()
        self.assertEqual(code, 1)
        self.assertFalse(marker.exists())
        self.assertEqual(self.harnexus.calls, [])

    def test_lost_rereview_answer_blocks_resend(self):
        self.assertEqual(self.review(answers=[created("r1", "gpt-6.1-sol")])[0], 0)
        self.commit("test: fix")
        self.assertEqual(self.review(answers=[DROP])[0], 1)
        self.commit("test: another fix")
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("never resend", err)
        self.assertEqual(len(self.harnexus.calls), 2)
        code, out, err = self.invoke(
            "resolve", "--request", self.write(self.data), "--sent"
        )
        self.assertEqual(code, 0, err)
        self.assertEqual(out["threadId"], "r1")

    def test_base_is_fixed_until_explicit_update(self):
        self.assertEqual(self.review(answers=[created("r1", "gpt-6.1-sol")])[0], 0)
        self.git("checkout", "-qb", "upstream")
        upstream = self.commit("test: upstream")
        self.git("checkout", "-q", "-")
        self.git("merge", "-q", "--no-edit", upstream)
        head = self.commit("test: worker")
        self.data["baseBranch"] = "upstream"
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("--update-base", err)
        code, _, err = self.review("--update-base", answers=[{"outcome": "done"}])
        self.assertEqual(code, 0, err)
        self.assertIn(
            upstream + "..." + head, self.harnexus.calls[-1]["arguments"]["prompt"]
        )

    def test_runs_only_plumbing_git_in_worker_worktrees(self):
        git_calls = []
        real_run = subprocess.run

        def record(command, **kwargs):
            git_calls.append(command)
            return real_run(command, **kwargs)

        with mock.patch.object(handoff.subprocess, "run", record):
            code, _, err = self.review(answers=[created("r1", "gpt-6.1-sol")])
        self.assertEqual(code, 0, err)
        self.assertTrue(git_calls)
        for command in git_calls:
            self.assertEqual(command[:7], ["git", *handoff.GIT_SAFETY])
            self.assertIn("protocol.allow=never", command)
            self.assertIn(command[9], ("rev-parse", "merge-base"))
        outside = self.root / "outside"
        outside.mkdir()
        self.data["checkout"] = str(outside)
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("worker worktree", err)
        link = self.codex / "worktrees/link"
        link.symlink_to(outside)
        self.data["checkout"] = str(link)
        self.assertEqual(self.review()[0], 1)

    def test_never_writes_into_the_checkout(self):
        before = sorted(self.checkout.iterdir())
        self.assertEqual(self.review(answers=[created("r1", "gpt-6.1-sol")])[0], 0)
        self.commit("test: fix")
        self.assertEqual(self.review(answers=[{"outcome": "done"}])[0], 0)
        self.assertEqual(sorted(self.checkout.iterdir()), before)

    def test_reviewer_cannot_be_the_worker_and_request_worker_must_match(self):
        self.data["workerChatId"] = "worker"
        self.assertEqual(self.review(answers=[DROP])[0], 1)
        request = self.write(self.data)
        code, _, err = self.invoke(
            "resolve", "--request", request, "--sent", "--thread-id", "worker"
        )
        self.assertEqual(code, 1)
        self.assertIn("cannot review itself", err)
        self.data["workerChatId"] = "someone-else"
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("must equal CODEX_THREAD_ID", err)

    def test_rejects_missing_caller(self):
        self.env["CODEX_THREAD_ID"] = ""
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("CODEX_THREAD_ID", err)

    def test_legacy_states_resume_or_refuse(self):
        legacy = {
            "identifier": "example",
            "worker": "Codex",
            "workerId": "worker",
            "projectId": "project",
            "checkout": str(self.checkout),
            "base": self.base,
            "head": self.base,
        }
        state = self.checkout / ".reviewctl/state.json"
        state.parent.mkdir()
        state.write_text(
            json.dumps({"reviewer": None, "pending_create": True, "candidate": legacy})
        )
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("legacy reviewctl creation is pending", err)
        state.write_text(json.dumps({"reviewer": "r0", "candidate": legacy}))
        self.commit("test: fix")
        code, out, err = self.review(answers=[{"outcome": "done"}])
        self.assertEqual(code, 0, err)
        self.assertEqual(self.harnexus.calls[-1]["arguments"]["threadId"], "r0")
        self.assertEqual(json.loads(state.read_text())["reviewer"], "r0")

    def test_symlinked_legacy_state_is_refused(self):
        target = self.root / "elsewhere.json"
        target.write_text(json.dumps({"reviewer": "r0", "candidate": {}}))
        (self.checkout / ".reviewctl").mkdir()
        (self.checkout / ".reviewctl/state.json").symlink_to(target)
        code, _, err = self.review()
        self.assertEqual(code, 1)
        self.assertIn("symlinked", err)


if __name__ == "__main__":
    unittest.main()
