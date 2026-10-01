import importlib.machinery
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "dot_claude" / "scripts" / "executable_sandbox-report.py"
HOME = "/Users/someone"


def load_report():
    loader = importlib.machinery.SourceFileLoader("sandbox_report", str(SCRIPT))
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


class SandboxReportTest(unittest.TestCase):
    def setUp(self):
        self.report = load_report()

    def scan(self, records):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "session.jsonl"
            path.write_text("\n".join(json.dumps(r) for r in records))
            return self.report.scan([path], HOME)

    def test_command_head_skips_cd_and_options(self):
        head = self.report.command_head
        self.assertEqual(head("cd ~/repo && git -C x commit -m y"), "git commit")
        self.assertEqual(head("FOO=1 nix develop -c make"), "nix develop")
        self.assertEqual(head("env -u A B=1 bun test"), "bun test")
        self.assertEqual(head("X=1; for c in a b; do echo $c; done"), "for")
        self.assertEqual(head("touch file"), "touch")

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


if __name__ == "__main__":
    unittest.main()
