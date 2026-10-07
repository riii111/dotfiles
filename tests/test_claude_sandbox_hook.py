import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "dot_claude" / "hooks" / "executable_sandbox-excluded-compound.py"
SETTINGS = ROOT / "dot_claude" / "settings.json.tmpl"


def load_hook():
    loader = importlib.machinery.SourceFileLoader("sandbox_hook", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def excluded_commands():
    block = re.search(r'"excludedCommands": (\[[^\]]*\])', SETTINGS.read_text())
    assert block is not None
    return json.loads(block.group(1))


HOOK = load_hook()
PATTERNS = excluded_commands()

ALLOWED = [
    "git status",
    "git log --oneline -n 5",
    "git log --format='%h;%s|%an' -n 3",
    "git grep 'foo|bar && baz'",
    'git commit -m "fix(hook): a; b | c"',
    "git status 2>&1",
    "git status >/dev/null 2>&1",
    "git status 2>/dev/null",
    "git status;",
    "git status\n",
    "/usr/bin/git status",
    "cd x && git status",
    "cd ~/ghq/repo && git status && git diff",
    "git status && git diff",
    "git fetch origin; git status || gh pr view 1",
    "git log | rg foo",
    "git log | rg -i -e foo",
    "git diff | sort",
    "git diff | sort -rn",
    "git diff | head -20",
    "git log | tail -n 5",
    "git diff --stat | wc -l",
    "git log | cut -d ' ' -f 1",
    "git log | uniq -c",
    "git log | tr a-z A-Z",
    "gh pr view 1 --json body | jq -r .body",
    "git commit -m \"$(cat <<'EOF'\nfeat: add x\n\nbody; with | and $(rm)\nEOF\n)\"",
    "harnexus-task launch --request request.json",
    "FOO=1 git status",
    "cp a b && mv c d",
    "ls | rg git",
    "bun run build && bun run lint",
]

DENIED = [
    "git status; cp /tmp/evil ~/.local/bin/harnexus-task",
    "git status && cp /tmp/evil ~/.local/bin/harnexus-task",
    "git status || cp a b",
    "git status\ncp a b",
    "cp /tmp/evil ~/.local/bin/harnexus-task; git status",
    "cd $HOME && git status",
    "cd x; git status",
    "git show HEAD:evil | sh",
    "git status & cp a b",
    "git fetch &",
    "git log > /tmp/out",
    "git log >> out.txt",
    "git log &> out.txt",
    "git log | sort -o x",
    "git log | sort --output=x",
    "git x | rg --pre=y z",
    "git log | rg foo /etc/passwd",
    "git log | head | sh",
    "git log | rg foo | sort",
    "git log --format=$(rm x)",
    "git log --format=`rm x`",
    'git commit -m "$(rm x)"',
    "git diff <(cp a b)",
    "echo $(gh auth status)",
    "git commit -F - <<'EOF'\nmsg\nEOF",
    "git commit -m \"$(cat <<'EOF'\nmsg\nEOF\ncp a b\nEOF\n)\"",
    "FOO=1 git status; cp a b",
    "/usr/bin/git status; cp a b",
    "harnexus-task launch --request r.json && cp a b",
    "cargo test; cp a b",
    "(git status)",
    "git status 'unterminated; cp a b",
]


class SandboxExcludedCompoundTest(unittest.TestCase):
    def test_bun_run_is_not_excluded(self):
        self.assertNotIn("bun run *", PATTERNS)

    def test_allowed_commands(self):
        for command in ALLOWED:
            with self.subTest(command=command):
                self.assertIsNone(HOOK.check(command, PATTERNS))

    def test_denied_commands(self):
        for command in DENIED:
            with self.subTest(command=command):
                reason = HOOK.check(command, PATTERNS)
                self.assertIsNotNone(reason)
                self.assertIn("alone", reason)

    def run_hook(self, stdin, home, cwd=None):
        env = dict(os.environ, HOME=home)
        env.pop("CLAUDE_PROJECT_DIR", None)
        result = subprocess.run(
            ["python3", "-I", str(SCRIPT)],
            input=stdin,
            capture_output=True,
            text=True,
            env=env,
            cwd=cwd,
            check=True,
        )
        return result.stdout

    def test_invalid_stdin_denies(self):
        with tempfile.TemporaryDirectory() as home:
            output = json.loads(self.run_hook("not json", home))
            self.assertEqual(output["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_invalid_project_excluded_commands_cover_everything(self):
        with tempfile.TemporaryDirectory() as home:
            project = Path(home, "project", ".claude")
            project.mkdir(parents=True)
            Path(project, "settings.json").write_text(
                json.dumps({"sandbox": {"excludedCommands": 5}})
            )
            event = {
                "cwd": str(project.parent),
                "tool_input": {"command": "ls; cp a b"},
            }
            output = json.loads(self.run_hook(json.dumps(event), home))
            self.assertEqual(output["hookSpecificOutput"]["permissionDecision"], "deny")
            event["tool_input"]["command"] = "ls"
            self.assertEqual(self.run_hook(json.dumps(event), home), "")

    def test_wildcard_pattern_covers_every_command(self):
        self.assertIsNotNone(HOOK.check("ls; cp a b", ["*"]))
        self.assertIsNone(HOOK.check("ls; cp a b", []))

    def test_hook_reads_settings_and_returns_deny(self):
        with tempfile.TemporaryDirectory() as home:
            settings = Path(home, ".claude", "settings.json")
            settings.parent.mkdir()
            settings.write_text(json.dumps({"sandbox": {"excludedCommands": PATTERNS}}))
            event = {
                "hook_event_name": "PreToolUse",
                "tool_name": "Bash",
                "cwd": home,
                "tool_input": {"command": "git status; cp a b"},
            }

            def run(command):
                event["tool_input"]["command"] = command
                return self.run_hook(json.dumps(event), home)

            output = json.loads(run("git status; cp a b"))["hookSpecificOutput"]
            self.assertEqual(output["hookEventName"], "PreToolUse")
            self.assertEqual(output["permissionDecision"], "deny")
            self.assertEqual(run("git status"), "")

    def test_settings_register_hook_for_bash(self):
        text = SETTINGS.read_text()
        self.assertIn('"command": "{{ .chezmoi.homeDir }}/.claude/hooks/sandbox-', text)
        self.assertTrue(SCRIPT.read_text().startswith("#!/usr/bin/python3 -I\n"))
        pre_tool_use = text[text.index('"PreToolUse"') : text.index('"PostToolUse"')]
        self.assertIn('"matcher": "Bash"', pre_tool_use)
        self.assertIn("sandbox-excluded-compound.py", pre_tool_use)


if __name__ == "__main__":
    unittest.main()
