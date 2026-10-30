import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/cloud-setup.sh"


class CloudSetupTest(unittest.TestCase):
    def setUp(self):
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        self.home = Path(home.name)

    def run_setup(self, **env):
        subprocess.run(
            ["bash", str(SCRIPT)],
            env={
                "PATH": os.environ["PATH"],
                "HOME": str(self.home),
                "GIT_CONFIG_NOSYSTEM": "1",
                **env,
            },
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads((self.home / ".claude/settings.json").read_text())

    def commands(self, settings):
        return {
            group["matcher"]: [
                hook["command"].rsplit("/", 1)[-1] for hook in group["hooks"]
            ]
            for group in settings["hooks"]["PreToolUse"]
        }

    def test_installs_the_pr_hooks_for_bash_and_github_mcp(self):
        settings = self.run_setup()

        self.assertEqual(
            self.commands(settings),
            {
                "^(Bash|mcp__.*)$": ["github-comment-check.py"],
                "^mcp__github__.*$": ["pr-format-check.py", "pr-state-check.py"],
                "Bash": [
                    "git-force-check.py",
                    "pr-format-check.py",
                    "pr-state-check.py",
                ],
            },
        )
        for name in ("github-comment-check", "git-force-check", "pr-format-check"):
            with self.subTest(name=name):
                hook = self.home / f".claude/hooks/{name}.py"
                self.assertEqual(
                    hook.read_text(),
                    (ROOT / f"dot_claude/hooks/executable_{name}.py").read_text(),
                )
                self.assertTrue(os.access(hook, os.X_OK))

    def test_running_again_keeps_other_settings_and_adds_nothing_twice(self):
        settings_path = self.home / ".claude/settings.json"
        settings_path.parent.mkdir(parents=True)
        settings_path.write_text(
            json.dumps(
                {
                    "permissions": {"deny": ["SearchPlugins"]},
                    "hooks": {
                        "PreToolUse": [
                            {
                                "matcher": "Write",
                                "hooks": [{"type": "command", "command": "true"}],
                            }
                        ]
                    },
                }
            )
        )

        self.run_setup()
        settings = self.run_setup()

        self.assertEqual(settings["permissions"], {"deny": ["SearchPlugins"]})
        self.assertEqual(
            [group["matcher"] for group in settings["hooks"]["PreToolUse"]],
            ["Write", "^(Bash|mcp__.*)$", "^mcp__github__.*$", "Bash"],
        )

    def test_sets_the_pr_language_only_when_given(self):
        self.run_setup()
        self.assertFalse((self.home / ".gitconfig").exists())

        self.run_setup(PR_LANGUAGE="ja")

        language = subprocess.run(
            ["git", "config", "--global", "--get", "pr.language"],
            env={"PATH": os.environ["PATH"], "HOME": str(self.home)},
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(language.stdout.strip(), "ja")


if __name__ == "__main__":
    unittest.main()
