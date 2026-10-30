import contextlib
import io
import json
import os
import re
import tempfile
import unittest
from pathlib import Path

from bin.lib.dot import cloud


ROOT = Path(__file__).resolve().parents[1]


class CloudInstallTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.codex = self.root / "codex"
        self.claude = self.root / "claude"

    def run_install(self, apply=True, skills=("task-worker", "pr-watch-link"), hooks=True, repo=ROOT):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cloud.run(repo, self.codex, self.claude, skills, hooks, apply)

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

    def test_reinstall_preserves_unchanged_files_and_updates_managed_content(self):
        repo = self.root / "source"
        source = repo / "dot_codex/skills/example/SKILL.md"
        source.parent.mkdir(parents=True)
        source.write_text("# First version\n")
        options = {"repo": repo, "skills": ("example",), "hooks": False}
        self.assertEqual(self.run_install(**options), 0)
        target = self.claude / "skills/example/SKILL.md"
        before = target.stat().st_mtime_ns
        self.assertEqual(self.run_install(**options), 0)
        self.assertEqual(target.stat().st_mtime_ns, before)
        source.write_text("# Updated version\n")
        self.assertEqual(self.run_install(**options), 0)
        for home in (self.codex, self.claude):
            self.assertEqual((home / "skills/example/SKILL.md").read_text(), source.read_text())

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

    def test_refuses_a_symlink_above_the_nearest_existing_directory(self):
        elsewhere = self.root / "elsewhere"
        (elsewhere / "task-worker").mkdir(parents=True)
        self.codex.mkdir()
        (self.codex / "skills").symlink_to(elsewhere)
        # skills/task-worker/references does not exist yet, so only the chain shows the link.
        self.assertEqual(self.run_install(), 1)
        self.assertEqual(list((elsewhere / "task-worker").iterdir()), [])

    def test_refuses_a_symlinked_manifest(self):
        self.claude.mkdir()
        target = self.root / "elsewhere.json"
        (self.claude / cloud.MANIFEST_NAME).symlink_to(target)
        self.assertEqual(self.run_install(), 1)
        self.assertFalse(target.exists())
        self.assertFalse((self.claude / "skills").exists())

    def test_quotes_hook_paths_with_spaces(self):
        self.claude = self.root / "my claude"
        self.codex = self.root / "my codex"
        self.assertEqual(self.run_install(), 0)
        import shlex

        settings = json.loads((self.claude / "settings.json").read_text())
        command = settings["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
        self.assertEqual(
            shlex.split(command),
            ["python3", str(self.claude / "hooks/github-comment-check.py")],
        )
        hooks = json.loads((self.codex / "hooks.json").read_text())
        command = hooks["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
        self.assertEqual(shlex.split(command)[1], str(self.codex / "hooks/pr-format-check.py"))

    def test_installs_linked_skills_and_every_relative_link_resolves(self):
        self.assertEqual(self.run_install(skills=cloud.DEFAULT_SKILLS, hooks=False), 0)
        installed = {path.name for path in (self.claude / "skills").iterdir()}
        # code-review is linked from the review skills, so it comes with them.
        self.assertIn("code-review", installed)
        checked = 0
        for home in (self.codex, self.claude):
            for doc in (home / "skills").rglob("*.md"):
                for target in cloud.relative_links(doc.read_text()):
                    pattern = re.sub(r"\{[^}]*\}", "*", target)
                    matches = list(doc.parent.glob(pattern))
                    self.assertTrue(matches, f"{doc} -> {target}")
                    checked += 1
        self.assertGreater(checked, 5)

    def test_a_link_in_a_code_block_is_not_a_link(self):
        text = "see [a](../x/y.md)\n```text\n[b](nowhere)\n```\nand `[c](also)`\n"
        self.assertEqual(cloud.relative_links(text), ["../x/y.md"])

    def test_a_read_only_home_names_the_alternative(self):
        locked = self.root / "locked"
        locked.mkdir()
        locked.chmod(0o500)
        self.addCleanup(locked.chmod, 0o700)
        if os.access(locked, os.W_OK):
            self.skipTest("running with privileges that ignore permissions")
        self.codex = locked / "codex"
        stderr = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            code = cloud.run(ROOT, self.codex, self.claude, ("task-worker",), False, True)
        self.assertEqual(code, 1)
        self.assertIn("--codex-home", stderr.getvalue())
        self.assertFalse((self.claude / "skills").exists())


if __name__ == "__main__":
    unittest.main()
