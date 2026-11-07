import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EVENTS = (
    "PreToolUse",
    "PostToolUse",
    "UserPromptSubmit",
    "PermissionRequest",
    "PermissionDenied",
)


def render(state, data, path):
    return json.loads(
        subprocess.run(
            [
                "chezmoi",
                "--config",
                str(ROOT / f"tests/chezmoi/{data}.toml"),
                "--source",
                str(ROOT),
                "--persistent-state",
                str(Path(state) / "state.boltdb"),
                "execute-template",
                "--file",
                str(ROOT / path),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    )


def commands(config):
    """Maps each event to (matcher, if, command name) rows, with the install folder dropped."""
    table = {}
    for event in EVENTS:
        for group in config["hooks"].get(event, []):
            for hook in group["hooks"]:
                if hook["type"] != "command":
                    continue
                table.setdefault(event, []).append(
                    (
                        group.get("matcher"),
                        hook.get("if"),
                        hook["command"].rsplit("/", 1)[-1],
                    )
                )
    return table


@unittest.skipUnless(shutil.which("chezmoi"), "chezmoi is not installed")
class AgentHooksRegistrationTest(unittest.TestCase):
    def test_rendered_configs_register_the_hooks(self):
        combined = "^(Bash|mcp__.*)$"
        expected = {
            ("personal", "dot_claude/settings.json.tmpl"): {
                "PreToolUse": [
                    (combined, None, "agent-hooks pre-tool-use --steer-tools")
                ],
                "PostToolUse": [
                    (
                        "Bash",
                        "Bash(git worktree add *)",
                        "agent-hooks worktree-post-add",
                    ),
                    # One pattern per hook, so `git -C DIR worktree add` needs its own.
                    (
                        "Bash",
                        "Bash(git -C * worktree add *)",
                        "agent-hooks worktree-post-add",
                    ),
                ],
                "UserPromptSubmit": [(None, None, "agent-hooks reply-reminder")],
                "PermissionRequest": [("*", None, "agent-hooks permission-log")],
                "PermissionDenied": [("*", None, "agent-hooks permission-log")],
            },
            ("work", "dot_claude/settings.json.tmpl"): {
                "PreToolUse": [
                    (
                        combined,
                        None,
                        "agent-hooks pre-tool-use --steer-tools"
                        " --require-draft --deny-force-push",
                    )
                ],
            },
            ("personal", "dot_codex/hooks.json.tmpl"): {
                "PreToolUse": [(combined, None, "agent-hooks pre-tool-use --codex")],
                "PermissionRequest": [
                    ("^Bash$", None, "agent-hooks permission-request")
                ],
            },
        }
        with tempfile.TemporaryDirectory() as state:
            for (data, path), events in expected.items():
                table = commands(render(state, data, path))
                for event, rows in events.items():
                    with self.subTest(data=data, path=path, event=event):
                        self.assertEqual(table.get(event), rows)
                if path.startswith("dot_codex"):
                    # Codex has no reply reminder, comment review or permission log.
                    self.assertEqual(set(table), {"PreToolUse", "PermissionRequest"})


if __name__ == "__main__":
    unittest.main()
