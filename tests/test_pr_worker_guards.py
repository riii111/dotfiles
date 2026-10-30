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

    def pr_url(self, owner):
        self.runner.return_value.stdout = json.dumps(
            {"url": f"https://github.com/{owner}/repo/pull/42"}
        )

    def test_merge_asks_outside_personal_repositories(self):
        for command in (
            "gh pr merge 42 --merge",
            "gh pr merge --auto --squash -R org/repo 42",
            "git status && gh pr merge 42 --subject 'fix: x' -b body",
        ):
            for owner, decision in (("sansaninc", "ask"), ("riii111", None)):
                with self.subTest(command=command, owner=owner):
                    self.pr_url(owner)
                    verdict = self.hook.check(command, "/tmp")
                    self.assertEqual(verdict and verdict[0], decision)
        self.assertEqual(
            self.runner.call_args.args[0][:3] + self.runner.call_args.args[0][-2:],
            ["gh", "pr", "view", "--json", "url"],
        )

    def test_merge_asks_when_its_repository_is_unknown(self):
        for error in (subprocess.CalledProcessError(1, "gh"), OSError()):
            self.runner.side_effect = error
            self.assertEqual(self.hook.check("gh pr merge 42", "/tmp")[0], "ask")
        self.runner.side_effect = None
        for output in ("garbage", "{}", '{"url": "https://example.com/o/r/pull/1"}'):
            self.runner.return_value.stdout = output
            self.assertEqual(self.hook.check("gh pr merge 42", "/tmp")[0], "ask")
        self.assertEqual(self.hook.check('gh pr merge "$PR"', "/tmp")[0], "ask")

    def test_api_merge_asks_outside_personal_repositories(self):
        for command in (
            "gh api -X PUT repos/sansaninc/app/pulls/1/merge",
            "gh api --method=PUT /repos/sansaninc/app/pulls/1/merge -f merge_method=squash",
            "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'",
            "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
        ):
            self.assertEqual(self.hook.check(command, "/tmp")[0], "ask", command)
        for command in (
            "gh api -X PUT repos/riii111/app/pulls/1/merge",
            "gh api repos/sansaninc/app/pulls/1/merge",
            "gh api repos/sansaninc/app/pulls/1",
        ):
            self.assertIsNone(self.hook.check(command, "/tmp"), command)
        self.runner.assert_not_called()

    def test_merge_help_does_not_query(self):
        self.assertIsNone(self.hook.check("gh pr merge --help", "/tmp"))
        self.runner.assert_not_called()

    def test_github_mcp_merges_ask_outside_personal_repositories(self):
        for operation in ("merge_pull_request", "enable_pr_auto_merge"):
            with self.subTest(operation=operation):
                self.assertIsNone(
                    self.hook.mcp_check(
                        "mcp__github__" + operation,
                        {"owner": "riii111", "repo": "harnexus", "pullNumber": 3},
                    )
                )
                self.assertEqual(
                    self.hook.mcp_check(
                        "mcp__github__" + operation,
                        {"owner": "acme", "repo": "app", "pullNumber": 3},
                    )[0],
                    "ask",
                )

    def test_github_mcp_cannot_change_base_or_convert_to_draft(self):
        for tool_input in ({"base": "main"}, {"draft": True}):
            with self.subTest(tool_input=tool_input):
                self.assertEqual(
                    self.hook.mcp_check(
                        "mcp__github__update_pull_request",
                        {"owner": "riii111", "pullNumber": 3, **tool_input},
                    )[0],
                    "deny",
                )
        for tool_input in ({"draft": False}, {"title": "fix: x"}):
            with self.subTest(tool_input=tool_input):
                self.assertIsNone(
                    self.hook.mcp_check(
                        "mcp__github__update_pull_request",
                        {"owner": "riii111", "pullNumber": 3, **tool_input},
                    )
                )
        self.runner.assert_not_called()

    def test_github_mcp_event_is_checked_without_a_command(self):
        event = json.dumps(
            {
                "tool_name": "mcp__github__merge_pull_request",
                "tool_input": {"owner": "acme", "repo": "app", "pullNumber": 3},
            }
        )
        output = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO(event)), redirect_stdout(output):
            self.assertEqual(self.hook.main(), 0)
        decision = json.loads(output.getvalue())["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "ask")

    def test_codex_copy_denies_merges(self):
        template = (ROOT / "dot_codex/hooks/pr-state-check.py.tmpl").read_text()
        self.assertIn(
            'replace "MERGE_DECISION = \\"ask\\"" "MERGE_DECISION = \\"deny\\""',
            template,
        )
        self.assertEqual(
            (ROOT / "dot_claude/hooks/executable_pr-state-check.py")
            .read_text()
            .count('MERGE_DECISION = "ask"'),
            1,
        )


if __name__ == "__main__":
    unittest.main()
