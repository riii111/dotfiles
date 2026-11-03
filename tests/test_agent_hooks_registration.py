import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class AgentHooksRegistrationTest(unittest.TestCase):
    def render(self, path):
        state = tempfile.TemporaryDirectory()
        self.addCleanup(state.cleanup)
        return subprocess.run(
            [
                "chezmoi",
                "--config",
                str(ROOT / "tests/chezmoi/personal.toml"),
                "--source",
                str(ROOT),
                "--persistent-state",
                str(Path(state.name) / "state.boltdb"),
                "execute-template",
                "--file",
                str(ROOT / path),
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout

    def test_rendered_configs_register_the_comment_check(self):
        for path in ("dot_codex/hooks.json.tmpl", "dot_claude/settings.json.tmpl"):
            with self.subTest(path=path):
                groups = json.loads(self.render(path))["hooks"]["PreToolUse"]
                self.assertTrue(
                    any(
                        group["matcher"] == "^(Bash|mcp__.*)$"
                        and any(
                            hook["command"].endswith(
                                "/.nix-profile/bin/agent-hooks github-comment-check"
                            )
                            for hook in group["hooks"]
                        )
                        for group in groups
                    )
                )

    def test_claude_settings_register_the_force_check_for_bash(self):
        groups = json.loads(self.render("dot_claude/settings.json.tmpl"))["hooks"][
            "PreToolUse"
        ]
        bash = [group for group in groups if group["matcher"] == "Bash"]
        self.assertTrue(
            any(
                hook["command"].endswith(
                    "/.nix-profile/bin/agent-hooks git-force-check"
                )
                for group in bash
                for hook in group["hooks"]
            )
        )

    def test_github_mcp_group_keeps_only_the_pr_checks(self):
        groups = json.loads(self.render("dot_claude/settings.json.tmpl"))["hooks"][
            "PreToolUse"
        ]
        mcp = [group for group in groups if group["matcher"] == "^mcp__github__.*$"]
        self.assertEqual(
            [
                hook["command"].rsplit("/", 1)[-1]
                for group in mcp
                for hook in group["hooks"]
            ],
            ["agent-hooks pr-format-check", "agent-hooks pr-state-check"],
        )

    def test_codex_denies_the_merges_claude_code_asks_about(self):
        for path, expected in (
            ("dot_claude/settings.json.tmpl", "agent-hooks pr-state-check"),
            ("dot_codex/hooks.json.tmpl", "agent-hooks pr-state-check --deny-merge"),
        ):
            with self.subTest(path=path):
                groups = json.loads(self.render(path))["hooks"]["PreToolUse"]
                commands = {
                    hook["command"].rsplit("/", 1)[-1]
                    for group in groups
                    for hook in group["hooks"]
                    if "pr-state-check" in hook.get("command", "")
                }
                self.assertEqual(commands, {expected})


if __name__ == "__main__":
    unittest.main()
