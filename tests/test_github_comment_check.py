import importlib.machinery
import importlib.util
import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "dot_claude/hooks/executable_github-comment-check.py"
loader = importlib.machinery.SourceFileLoader("github_comment_check", str(HOOK))
spec = importlib.util.spec_from_loader(loader.name, loader)
policy = importlib.util.module_from_spec(spec)
loader.exec_module(policy)


def bash(command):
    return {"tool_name": "Bash", "tool_input": {"command": command}}


class GithubCommentCheckTest(unittest.TestCase):
    def assert_denied(self, commands, expected):
        for command in commands:
            with self.subTest(command=command):
                self.assertEqual(policy.denied(bash(command)), expected)

    def test_denies_comment_posting_commands(self):
        self.assert_denied(
            [
                "gh pr comment 1 --body hi",
                "gh pr review 1 --comment -b hi",
                "/opt/homebrew/bin/gh -R owner/repo pr comment 1 -b hi",
                "GH_HOST=github.com gh pr comment 1 -b hi",
                "git status && gh pr comment 1 --body-file draft.md",
                "gh pr view 1\ngh pr comment 1 -b hi",
                "bash -lc 'gh pr comment 1 -b hi'",
                "gh pr close 1 --comment hi",
                "gh api repos/a/b/issues/1/comments -f body=hi",
                "gh api -X POST repos/a/b/pulls/1/comments --input draft.json",
                "gh api repos/a/b/pulls/1/comments/2/replies -f body=hi",
                "gh api --method PATCH repos/a/b/issues/comments/2 -f body=hi",
                "gh api -XPOST repos/a/b/pulls/1/reviews/2/events -f event=COMMENT",
                "gh api graphql -f 'query=mutation { addComment(input: {}) { clientMutationId } }'",
            ],
            True,
        )

    def test_allows_reads_and_unrelated_commands(self):
        self.assert_denied(
            [
                "gh pr view 1 --json title,body",
                "gh-loupe pr show 1",
                "gh api repos/a/b/issues/1/comments",
                "gh api -X GET repos/a/b/pulls/1/comments -f per_page=100",
                "gh api -X DELETE repos/a/b/pulls/1/reviews/2",
                'gh api graphql -f \'query={ repository(owner: "a", name: "b") { name } }\'',
                "gh pr create --draft --title 'fix: title' --body hi",
                "gh issue comment 1 -b hi",
                "gh issue close 1 --comment hi",
                "rg 'gh pr comment' tests",
                "echo gh pr comment 1",
            ],
            False,
        )

    def test_denies_github_connector_comment_tools(self):
        for operation in policy.COMMENT_TOOLS:
            with self.subTest(operation=operation):
                self.assertTrue(
                    policy.denied({"tool_name": "mcp__codex_apps__github_" + operation})
                )
        for name in (
            "mcp__codex_apps__github_fetch_pr_comments",
            "mcp__codex_apps__github_create_pull_request",
            "mcp__codex_app__send_message_to_thread",
        ):
            with self.subTest(name=name):
                self.assertFalse(
                    policy.denied({"tool_name": name, "tool_input": {"body": "hi"}})
                )

    def test_hook_output(self):
        result = subprocess.run(
            ["python3", str(HOOK)],
            input=json.dumps(bash("gh pr comment 1 -b hi")),
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(
            json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"],
            "deny",
        )
        result = subprocess.run(
            ["python3", str(HOOK)],
            input=json.dumps(bash("git status")),
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertEqual(result.stdout, "")

    def test_rendered_configs_register_the_hook(self):
        def render(path):
            return subprocess.run(
                ["chezmoi", "execute-template", "--file", str(ROOT / path)],
                cwd=ROOT,
                capture_output=True,
                text=True,
                check=True,
            ).stdout

        self.assertEqual(
            render("dot_codex/hooks/github-comment-check.py.tmpl"), HOOK.read_text()
        )
        for path in ("dot_codex/hooks.json.tmpl", "dot_claude/settings.json.tmpl"):
            with self.subTest(path=path):
                groups = json.loads(render(path))["hooks"]["PreToolUse"]
                self.assertTrue(
                    any(
                        group["matcher"] == "^(Bash|mcp__.*)$"
                        and any(
                            "github-comment-check.py" in hook["command"]
                            for hook in group["hooks"]
                        )
                        for group in groups
                    )
                )


if __name__ == "__main__":
    unittest.main()
