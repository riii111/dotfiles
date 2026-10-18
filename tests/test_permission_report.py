import importlib.machinery
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "dot_claude" / "scripts" / "executable_permission-report.py"
HOME = "/Users/someone"


def load_report():
    loader = importlib.machinery.SourceFileLoader("permission_report", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def bash(tool_id, command, unsandboxed=False):
    tool_input = {"command": command}
    if unsandboxed:
        tool_input["dangerouslyDisableSandbox"] = True
    return {
        "type": "assistant",
        "message": {
            "content": [
                {"type": "tool_use", "id": tool_id, "name": "Bash", "input": tool_input}
            ]
        },
    }


def result(tool_id, output):
    return {
        "type": "user",
        "message": {
            "content": [
                {"type": "tool_result", "tool_use_id": tool_id, "content": output}
            ]
        },
    }


class PermissionReportTest(unittest.TestCase):
    def setUp(self):
        self.report = load_report()

    def scan(self, records):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "session.jsonl"
            path.write_text("\n".join(json.dumps(r) for r in records))
            return self.report.scan([path], HOME)

    def test_counts_write_denials_and_reruns(self):
        lock = f"{HOME}/ghq/repo/.git/index.lock"
        reruns, failed, writes, hosts = self.scan(
            [
                bash("1", "git add file"),
                result(
                    "1", f"fatal: Unable to create '{lock}': Operation not permitted"
                ),
                bash("2", "git add file", unsandboxed=True),
                result(
                    "2", "fatal: Unable to create '/elsewhere': Operation not permitted"
                ),
            ]
        )
        self.assertEqual(reruns, {"git add": 1})
        self.assertEqual(failed, {"git add": 1})
        self.assertEqual(writes, {"~/ghq/repo/.git": 1})
        self.assertEqual(hosts, {})

    def test_counts_refused_hosts(self):
        _, failed, _, hosts = self.scan(
            [
                bash("1", "curl https://example.com"),
                result(
                    "1",
                    [
                        {
                            "type": "text",
                            "text": "<sandbox_violations>\ndeny network-outbound example.com:443\n</sandbox_violations>",
                        }
                    ],
                ),
            ]
        )
        self.assertEqual(hosts, {"example.com": 1})
        self.assertEqual(failed, {})

    def scan_events(self, events, since="2026-10-01T00:00:00+09:00"):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "events.jsonl"
            path.write_text("\n".join(json.dumps(e) for e in events) + "\nnot json\n")
            cutoff = self.report.datetime.fromisoformat(since).timestamp()
            return self.report.scan_events(path, cutoff, home=HOME)

    def test_counts_recorded_prompts_and_denials(self):
        report = self.scan_events(
            [
                event(
                    "PermissionRequest", "for f in a; do gh pr view; done", session="s1"
                ),
                event(
                    "PermissionRequest",
                    "git push origin main",
                    session="s1",
                    unsandboxed=True,
                ),
                event("PermissionRequest", "git push origin main", session="s2"),
                event(
                    "PermissionDenied",
                    "gh pr merge 1",
                    reason="[Data Exfiltration] moves data",
                ),
                {
                    "time": "2026-10-04T10:03:00+0900",
                    "event": "PermissionRequest",
                    "tool": "WebFetch",
                    "cwd": f"{HOME}/ghq/repo",
                },
                event("PermissionRequest", "old", time="2020-01-01T00:00:00+0900"),
            ]
        )
        self.assertEqual(
            report["shapes"]["PermissionRequest"],
            {
                "loop": 1,
                "single command (rerun outside the sandbox)": 1,
                "single command": 1,
                "tool: WebFetch": 1,
            },
        )
        self.assertEqual(
            report["commands"]["PermissionRequest"],
            {
                "for  (1 sessions)": 1,
                "git push  (2 sessions)": 2,
                "tool: WebFetch  (1 sessions)": 1,
            },
        )
        self.assertEqual(report["places"]["PermissionRequest"], {"~/ghq/repo": 4})
        self.assertEqual(report["shapes"]["PermissionDenied"], {"single command": 1})
        self.assertEqual(report["causes"], {"rule: Data Exfiltration": 1})
        self.assertEqual(
            report["commands"]["PermissionDenied"],
            {"rule: Data Exfiltration | gh pr  (1 sessions)": 1},
        )


def event(
    name,
    command,
    time="2026-10-04T10:00:00+0900",
    session="s",
    reason=None,
    unsandboxed=False,
):
    record = {
        "time": time,
        "event": name,
        "tool": "Bash",
        "command": command,
        "session": session,
        "cwd": f"{HOME}/ghq/repo",
        "unsandboxed": unsandboxed,
    }
    if reason is not None:
        record["reason"] = reason
    return record


class LogPermissionEventTest(unittest.TestCase):
    def setUp(self):
        path = ROOT / "dot_claude" / "hooks" / "executable_log-permission-event.py"
        loader = importlib.machinery.SourceFileLoader("log_permission_event", str(path))
        spec = importlib.util.spec_from_loader(loader.name, loader)
        assert spec is not None and spec.loader is not None
        self.hook = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.hook)

    def run_hook(self, payload, log):
        self.hook.LOG = log
        stdin = io.StringIO(
            payload if isinstance(payload, str) else json.dumps(payload)
        )
        stdout = io.StringIO()
        with mock.patch.object(self.hook.sys, "stdin", stdin), redirect_stdout(stdout):
            self.assertEqual(self.hook.main(), 0)
        return stdout.getvalue()

    def test_records_bash_prompt_without_deciding(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "state" / "events.jsonl"
            output = self.run_hook(
                {
                    "hook_event_name": "PermissionRequest",
                    "session_id": "s1",
                    "cwd": "/repo",
                    "permission_mode": "auto",
                    "tool_name": "Bash",
                    "tool_input": {
                        "command": "x" * 600,
                        "dangerouslyDisableSandbox": True,
                    },
                },
                log,
            )
            record = json.loads(log.read_text())
            mode = log.stat().st_mode & 0o777
        self.assertEqual(output, "")
        self.assertEqual(mode, 0o600)
        self.assertEqual(record["event"], "PermissionRequest")
        self.assertEqual(len(record["command"]), 500)
        self.assertTrue(record["unsandboxed"])

    def test_bad_input_is_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "events.jsonl"
            self.assertEqual(self.run_hook("not json", log), "")
            self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
