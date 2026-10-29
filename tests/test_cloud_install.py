import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

from bin.lib.dot import cli, cloud


ROOT = Path(__file__).resolve().parents[1]


class CloudInstallTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.codex = self.root / "codex"
        self.claude = self.root / "claude"

    def run_install(self, apply=True, skills=("task-worker", "pr-watch-link"), hooks=True):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cloud.run(ROOT, self.codex, self.claude, skills, hooks, apply)

    def test_dry_run_writes_nothing(self):
        self.assertEqual(self.run_install(apply=False), 0)
        self.assertFalse(self.codex.exists())
        self.assertFalse(self.claude.exists())

    def test_installs_skills_into_both_homes_from_the_single_source(self):
        self.assertEqual(self.run_install(), 0)
        source = (ROOT / "dot_codex/skills/task-worker/SKILL.md").read_bytes()
        for home in (self.codex, self.claude):
            self.assertEqual((home / "skills/task-worker/SKILL.md").read_bytes(), source)
            self.assertTrue((home / "skills/pr-watch-link/SKILL.md").is_file())
            manifest = json.loads((home / cloud.MANIFEST_NAME).read_text())
            self.assertIn(str(home / "skills/task-worker/SKILL.md"), manifest["files"])

    def test_default_skills_all_exist_and_their_templates_are_skipped_not_rendered(self):
        plan = cloud.build_plan(ROOT, self.codex, self.claude, cloud.DEFAULT_SKILLS, False)
        self.assertTrue(plan.files)
        self.assertFalse([path for path in plan.files if path.name.endswith(".tmpl")])

    def test_second_run_changes_nothing_and_a_changed_source_updates(self):
        self.assertEqual(self.run_install(), 0)
        target = self.claude / "skills/task-worker/SKILL.md"
        before = target.stat().st_mtime_ns
        self.assertEqual(self.run_install(), 0)
        self.assertEqual(target.stat().st_mtime_ns, before)

    def test_refuses_to_overwrite_a_file_it_did_not_write(self):
        target = self.claude / "settings.json"
        target.parent.mkdir(parents=True)
        target.write_text('{"mine": true}')
        self.assertEqual(self.run_install(), 1)
        self.assertEqual(target.read_text(), '{"mine": true}')
        self.assertFalse((self.codex / "skills").exists())

    def test_refuses_a_file_edited_after_it_was_installed(self):
        self.assertEqual(self.run_install(), 0)
        target = self.codex / "hooks.json"
        target.write_text("{}")
        self.assertEqual(self.run_install(), 1)
        self.assertEqual(target.read_text(), "{}")

    def test_refuses_to_write_through_a_symlink(self):
        elsewhere = self.root / "elsewhere"
        elsewhere.mkdir()
        self.codex.mkdir()
        (self.codex / "skills").symlink_to(elsewhere)
        self.assertEqual(self.run_install(), 1)
        self.assertEqual(list(elsewhere.iterdir()), [])

    def test_rejects_a_bad_skill_name_and_a_relative_home(self):
        for name in ("../x", "Task", "a/b", "nope-missing"):
            with self.subTest(name=name):
                self.assertEqual(self.run_install(skills=(name,)), 1)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(
                cloud.run(ROOT, Path("rel"), self.claude, ("task-worker",), False, False), 1
            )

    def test_hooks_use_the_target_paths_and_no_local_paths(self):
        self.assertEqual(self.run_install(), 0)
        claude = json.loads((self.claude / "settings.json").read_text())
        commands = [
            hook["command"]
            for group in claude["hooks"]["PreToolUse"]
            for hook in group["hooks"]
        ]
        self.assertIn(f"python3 {self.claude}/hooks/git-force-check.py --deny-force-push", commands)
        codex = json.loads((self.codex / "hooks.json").read_text())
        text = json.dumps(codex) + json.dumps(claude)
        for local in ("/Users/", "herdr", "affected-agent", "{{", "osascript"):
            self.assertNotIn(local, text)
        for script in cloud.CLAUDE_HOOKS:
            self.assertTrue(os.access(self.claude / "hooks" / script, os.X_OK))
        self.assertFalse((self.codex / "hooks/permission_request.py").exists())

    def test_pr_state_hook_denies_merges_in_both_homes(self):
        self.assertEqual(self.run_install(), 0)
        for home in (self.claude, self.codex):
            text = (home / "hooks/pr-state-check.py").read_text()
            self.assertIn('MERGE_DECISION = "deny"', text)
            self.assertNotIn('MERGE_DECISION = "ask"', text)

    def test_no_hooks_installs_skills_only(self):
        self.assertEqual(self.run_install(hooks=False), 0)
        self.assertFalse((self.claude / "settings.json").exists())
        self.assertFalse((self.codex / "hooks").exists())

    def test_codex_hooks_come_from_the_sources_chezmoi_includes(self):
        # Keeps the Cloud subset from drifting from the local Codex copies.
        plan = cloud.build_plan(ROOT, self.codex, self.claude, (), True)
        for script in cloud.CODEX_HOOKS:
            template = (ROOT / "dot_codex/hooks" / f"{script}.tmpl").read_text()
            source = f"dot_claude/hooks/executable_{script}"
            self.assertIn(f'include "{source}"', template)
            expected = (ROOT / source).read_bytes()
            if script == "pr-state-check.py":
                old, new = cloud.ASK_TO_DENY
                self.assertIn(new.replace('"', '\\"'), template)
                expected = expected.replace(old.encode(), new.encode())
            self.assertEqual(plan.files[self.codex / "hooks" / script][0], expected)

    def test_dotctl_registers_the_command(self):
        parser = cli.build_parser()
        args = parser.parse_args(["cloud-install", "--skill", "task-worker", "--apply"])
        self.assertTrue(args.apply)
        self.assertEqual(args.skill, ["task-worker"])


if __name__ == "__main__":
    unittest.main()
