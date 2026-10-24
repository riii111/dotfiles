import importlib.machinery
import importlib.util
import io
import json
import subprocess
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_hook(name):
    loader = importlib.machinery.SourceFileLoader(
        name, str(ROOT / "dot_claude/hooks" / f"executable_{name}.py")
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class PrStateTest(unittest.TestCase):
    def setUp(self):
        self.hook = load_hook("pr-state-check")
        self.runner = mock.patch.object(self.hook.subprocess, "run").start()
        self.addCleanup(mock.patch.stopall)

    def state(self, value):
        self.runner.return_value.stdout = json.dumps({"isDraft": value})

    def test_only_draft_can_be_changed(self):
        for command in (
            "gh pr ready 42 --undo",
            "gh pr edit 42 --base main",
            "gh pr edit --base=main 42",
            "gh pr edit -Bmain 42",
            "gh pr edit 42 -B main --title 'fix: title'",
            "git status && gh pr ready 42 --undo",
            "gh pr view 42\ngh pr ready 42 --undo",
            "gh pr view 42;\ngh pr ready 42 --undo",
        ):
            for draft in (True, False):
                with self.subTest(command=command, draft=draft):
                    self.state(draft)
                    self.assertEqual(bool(self.hook.check(command, "/tmp")), not draft)

    def test_resolves_same_target_and_repository(self):
        self.state(True)
        for command in (
            "gh pr edit 42 --base main -R org/repo",
            "gh -R org/repo pr edit --base main 42",
            "gh pr --repo org/repo edit --base main 42",
            "gh pr -R org/repo edit --base main 42",
            "gh pr edit --repo=org/repo --base main 42",
            "gh pr edit -Rorg/repo 42 -B main",
        ):
            self.assertIsNone(self.hook.check(command, "/tmp"))
            self.assertEqual(
                self.runner.call_args.args[0],
                [
                    "gh",
                    "pr",
                    "view",
                    "42",
                    "--repo",
                    "org/repo",
                    "--json",
                    "isDraft",
                ],
            )

    def test_url_branch_and_current_branch(self):
        self.state(True)
        for target in ("https://github.com/org/repo/pull/42", "feature/change", ""):
            self.assertIsNone(self.hook.check(f"gh pr ready {target} --undo", "/tmp"))
            self.assertEqual(
                self.runner.call_args.args[0],
                [
                    "gh",
                    "pr",
                    "view",
                    *([target] if target else []),
                    "--json",
                    "isDraft",
                ],
            )

    def test_environment_matches_the_mutation(self):
        self.state(True)
        self.assertIsNone(
            self.hook.check("GH_REPO=org/repo gh pr ready 42 --undo", "/tmp")
        )
        self.assertEqual(self.runner.call_args.kwargs["env"]["GH_REPO"], "org/repo")

    def test_directory_change(self):
        self.state(True)
        self.assertIsNone(
            self.hook.check("cd /tmp/repo && gh pr edit 42 -B main", "/tmp")
        )
        self.assertEqual(
            self.runner.call_args.kwargs["cwd"], str(Path("/tmp/repo").resolve())
        )

    def test_subshell_restores_the_original_repository(self):
        self.state(False)
        command = "(cd /tmp/draft && gh pr view 1) && gh pr edit 1 -B main"
        self.assertIsNotNone(self.hook.check(command, "/tmp/open"))
        self.assertEqual(self.runner.call_args.kwargs["cwd"], "/tmp/open")

    def test_redirections_do_not_change_pr_identity(self):
        for suffix in (
            " </dev/null",
            " > /tmp/result",
            " 2>/dev/null",
            " >/tmp/out 2>&1",
            " &>/tmp/result",
            " >> /tmp/result",
            " # explanatory comment",
        ):
            for draft in (True, False):
                self.state(draft)
                self.assertEqual(
                    bool(self.hook.check("gh pr edit 1 --base main" + suffix, "/tmp")),
                    not draft,
                    suffix,
                )
                self.assertEqual(
                    self.runner.call_args.args[0],
                    [
                        "gh",
                        "pr",
                        "view",
                        "1",
                        "--json",
                        "isDraft",
                    ],
                )

    def test_quoted_shell_characters_remain_argument_values(self):
        self.state(True)
        self.assertIsNone(
            self.hook.check(
                "gh pr edit 42 -B main --body '(quoted) > output; # comment'",
                "/tmp",
            )
        )
        self.assertEqual(
            self.runner.call_args.args[0],
            [
                "gh",
                "pr",
                "view",
                "42",
                "--json",
                "isDraft",
            ],
        )

    def test_unrelated_commands_do_not_query(self):
        for command in (
            "gh pr ready 42",
            "gh pr edit 42 --add-label bug",
            "git status",
            "echo 'gh pr ready 42 --undo'",
            "gh pr edit 42 --body 'use --base main'",
        ):
            self.assertIsNone(self.hook.check(command, "/tmp"), command)
        self.runner.assert_not_called()

    def test_lookup_failure_is_denied(self):
        for error in (
            subprocess.TimeoutExpired("gh", 5),
            subprocess.CalledProcessError(1, "gh"),
            OSError(),
        ):
            self.runner.side_effect = error
            self.assertIsNotNone(self.hook.check("gh pr ready 42 --undo", "/tmp"))
        self.runner.side_effect = None
        for output in ("garbage", "{}", '{"isDraft": "true"}'):
            self.runner.return_value.stdout = output
            self.assertIsNotNone(self.hook.check("gh pr ready 42 --undo", "/tmp"))

    def test_dynamic_identity_is_denied(self):
        for command in (
            'gh pr ready "$PR" --undo',
            'gh pr ready 42 --undo -R "$REPO"',
            'cd "$REPO" && gh pr edit 42 -B main',
        ):
            self.assertIsNotNone(self.hook.check(command, "/tmp"))
        self.runner.assert_not_called()

    def test_emits_pretooluse_deny(self):
        self.state(False)
        output = io.StringIO()
        event = {"tool_input": {"command": "gh pr ready 42 --undo"}, "cwd": "/tmp"}
        with (
            mock.patch("sys.stdin", io.StringIO(json.dumps(event))),
            redirect_stdout(output),
        ):
            self.hook.main()
        self.assertEqual(
            json.loads(output.getvalue())["hookSpecificOutput"]["permissionDecision"],
            "deny",
        )


class ReferenceLinkTest(unittest.TestCase):
    def setUp(self):
        self.hook = load_hook("reference-link-check")

    def test_explicit_unlinked_references(self):
        for message in (
            "Issue #42を確認しました",
            "PR#42を作成しました",
            "issue #1 と PR #2",
        ):
            self.assertTrue(self.hook.missing_links(message), message)

    def test_excludes_code_quotes_and_links(self):
        for message in (
            "[PR #42](https://github.com/org/repo/pull/42)",
            "[Issue #42](https://github.com/org/repo/issues/42)",
            "`Issue #42`",
            "```text\nPR #42\n```",
            "~~~\nIssue #42\n~~~",
            "> PR #42",
            "#42",
            "## 42件の結果",
            "C#12",
        ):
            self.assertFalse(self.hook.missing_links(message), message)

    def test_link_elsewhere_does_not_hide_missing_reference(self):
        self.assertTrue(
            self.hook.missing_links("[PR #1](https://github.com/o/r/pull/1) と PR #2")
        )

    def test_asks_to_append_links_instead_of_rewriting(self):
        event = {"last_assistant_message": "PR #42", "stop_hook_active": False}
        output = io.StringIO()
        with (
            mock.patch("sys.stdin", io.StringIO(json.dumps(event))),
            redirect_stdout(output),
        ):
            self.hook.main()
        reason = json.loads(output.getvalue())["reason"]
        self.assertIn("繰り返さない", reason)
        self.assertIn("追記", reason)

    def test_no_continuation_loop(self):
        for active in (False, True):
            event = {"last_assistant_message": "PR #42", "stop_hook_active": active}
            output = io.StringIO()
            with (
                mock.patch("sys.stdin", io.StringIO(json.dumps(event))),
                redirect_stdout(output),
            ):
                self.hook.main()
            self.assertEqual(bool(output.getvalue()), not active)
        event = {"last_assistant_message": None}
        with mock.patch("sys.stdin", io.StringIO(json.dumps(event))):
            self.assertEqual(self.hook.main(), 0)


if __name__ == "__main__":
    unittest.main()
