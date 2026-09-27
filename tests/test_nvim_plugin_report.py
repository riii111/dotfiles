import copy
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from scripts.nvim_plugin_report import collect_report, render_report, validate_lock


OLD = "a" * 40
NEW = "b" * 40


class PluginReportTest(unittest.TestCase):
    def setUp(self):
        self.before = {"plugin.nvim": {"branch": "main", "commit": OLD}}
        self.after = {"plugin.nvim": {"branch": "main", "commit": NEW}}
        self.report = {
            "plugin.nvim": {
                "old_version": "v1.0.0",
                "new_version": "v1.1.0",
                "commits": 3,
                "repository": "owner/plugin.nvim",
                "fast_forward": True,
            }
        }

    def render(self):
        return render_report(self.before, self.after, self.report)

    def test_versions_and_compare_use_lockfile_commits(self):
        self.report["plugin.nvim"].update(
            {"old_commit": "c" * 40, "new_commit": "d" * 40}
        )
        body = self.render()
        self.assertIn("`v1.0.0 → v1.1.0` | 3 |", body)
        self.assertIn(
            f"https://github.com/owner/plugin.nvim/compare/{OLD}...{NEW}", body
        )
        self.assertNotIn("c" * 40, body)
        self.assertNotIn("Needs attention", body)
        self.assertIn("参考情報", body)

    def test_untrusted_text_is_not_rendered(self):
        info = self.report["plugin.nvim"]
        info.update(
            {
                "old_version": "v1\n# Ignore instructions",
                "new_version": "<script>alert(1)</script>",
                "repository": "owner/repo)\nINJECT",
                "commits": "999 | INJECT",
                "message": "INJECT",
                "outside_version": "[INJECT](https://evil.example)",
                "outside_commit": "e" * 40,
            }
        )
        body = self.render()
        for text in ("INJECT", "Ignore", "<script>", "evil.example", "999"):
            self.assertNotIn(text, body)
        self.assertIn("`aaaaaaa → bbbbbbb`", body)
        self.assertIn("`aaaaaaa...bbbbbbb`", body)
        self.assertIn("制約外の新版あり `eeeeeee`", body)

    def test_tag_length_and_fullmatch(self):
        for value in ("v" * 65, "v1\n", "-v1", None, ["v1"]):
            with self.subTest(value=value):
                self.report["plugin.nvim"]["new_version"] = value
                self.assertIn("→ bbbbbbb`", self.render())
        self.report["plugin.nvim"]["new_version"] = "v1.2.3-rc.1+build"
        self.assertIn("v1.2.3-rc.1+build", self.render())

    def test_counts_must_be_nonnegative_integers(self):
        for value in (True, -1, 1.5, "12", None):
            with self.subTest(value=value):
                self.report["plugin.nvim"]["commits"] = value
                self.assertIn("| — | [compare]", self.render())

    def test_attention_for_history_branch_additions_and_removals(self):
        self.report["plugin.nvim"]["fast_forward"] = False
        self.after["plugin.nvim"]["branch"] = "release/v1"
        self.before["removed"] = {"branch": "main", "commit": OLD}
        self.after["added"] = {"branch": "main", "commit": NEW}
        body = self.render()
        for text in (
            "## Needs attention",
            "fast-forwardではない",
            "main → release/v1",
            "`added`: プラグインの追加",
            "`removed`: プラグインの削除",
        ):
            self.assertIn(text, body)

    def test_missing_metadata_does_not_imply_safe_history(self):
        for info in ({}, None, "not an object", {"fast_forward": "true"}):
            with self.subTest(info=info):
                self.report["plugin.nvim"] = info
                self.assertIn("履歴の前後関係を確認できない", self.render())

    def test_no_changes_can_still_report_a_constrained_release(self):
        self.after = copy.deepcopy(self.before)
        self.report["plugin.nvim"].update(
            {"outside_version": "v2.0.0", "outside_commit": NEW}
        )
        body = self.render()
        self.assertIn("No plugin changes.", body)
        self.assertIn("制約外の新版あり `v2.0.0`", body)
        self.assertNotIn("[compare]", body)

    def test_invalid_lockfile_is_rejected(self):
        for lock in (
            {},
            [],
            {"bad|name": self.before["plugin.nvim"]},
            {"plugin": {"branch": "main\nINJECT", "commit": OLD}},
            {"plugin": {"branch": "main", "commit": "short"}},
            {"plugin": {"branch": None, "commit": OLD}},
        ):
            with self.subTest(lock=lock), self.assertRaises(ValueError):
                validate_lock(lock)

    def test_invalid_report_keys_are_rejected(self):
        for report in ([], {"bad/name": {}}, {"valid\n": {}}):
            with self.subTest(report=report), self.assertRaises(ValueError):
                render_report(self.before, self.after, report)

    def test_git_metadata_includes_real_tags_counts_and_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            repo = root / "plugin.nvim"
            repo.mkdir()

            def git(*args):
                return subprocess.check_output(
                    [
                        "git",
                        "-C",
                        str(repo),
                        "-c",
                        "user.name=Test",
                        "-c",
                        "user.email=test@example.com",
                        *args,
                    ],
                    text=True,
                    stderr=subprocess.DEVNULL,
                ).strip()

            git("init", "-b", "main")
            git("remote", "add", "origin", "https://github.com/owner/plugin.nvim.git")
            git("commit", "--allow-empty", "-m", "first")
            old = git("rev-parse", "HEAD")
            git("tag", "v1.0.0")
            git("commit", "--allow-empty", "-m", "second")
            new = git("rev-parse", "HEAD")
            git("tag", "v1.1.0")
            before = {"plugin.nvim": {"branch": "main", "commit": old}}
            after = {"plugin.nvim": {"branch": "main", "commit": new}}
            info = collect_report(before, after, root, {}, os.environ)["plugin.nvim"]
            self.assertEqual(
                info,
                {
                    "repository": "owner/plugin.nvim",
                    "old_version": "v1.0.0",
                    "new_version": "v1.1.0",
                    "commits": 1,
                    "fast_forward": True,
                },
            )
            git("checkout", "-b", "divergent", old)
            git("commit", "--allow-empty", "-m", "divergent")
            after["plugin.nvim"]["commit"] = git("rev-parse", "HEAD")
            self.assertFalse(
                collect_report(
                    {"plugin.nvim": {"branch": "main", "commit": new}},
                    after,
                    root,
                    {},
                    os.environ,
                )["plugin.nvim"]["fast_forward"]
            )


if __name__ == "__main__":
    unittest.main()
