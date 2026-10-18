import importlib.machinery
import importlib.util
import io
import json
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "dot_claude" / "hooks" / "executable_pr-format-check.py"

GOOD_BODY = """close #12

ログが長く失敗箇所を探しにくいため、成功テストの出力を省く

- 失敗したテストだけを出力する
- 既定の詳細度は変えない
"""


def load_check():
    loader = importlib.machinery.SourceFileLoader("pr_format_check", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def create_command(body, title="ci: テストのログを減らす"):
    return f"""gh pr create --draft --title "{title}" --body "$(cat <<'EOF'
{body}EOF
)\""""


class PrFormatCheckTest(unittest.TestCase):
    def setUp(self):
        self.check = load_check()

    def denies(self, command):
        event = json.dumps({"tool_input": {"command": command}})
        output = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO(event)), redirect_stdout(output):
            self.assertEqual(self.check.main(), 0)
        if not output.getvalue():
            return False
        decision = json.loads(output.getvalue())["hookSpecificOutput"]
        self.assertEqual(decision["permissionDecision"], "deny")
        return True

    def test_accepts_a_conforming_pr(self):
        self.assertFalse(self.denies(create_command(GOOD_BODY)))

    def test_ignores_other_commands(self):
        self.assertFalse(self.denies("git status"))
        self.assertFalse(self.denies("gh pr view 1 --json title,body"))
        self.assertFalse(self.denies("gh pr edit 1 --add-label bug"))

    def test_survives_unparsable_input(self):
        output = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO("not json")), redirect_stdout(output):
            self.assertEqual(self.check.main(), 0)
        self.assertEqual(output.getvalue(), "")

    def test_denies_a_title_without_a_conventional_type(self):
        self.assertTrue(
            self.denies(create_command(GOOD_BODY, title="テストのログを減らす"))
        )

    def test_denies_a_space_between_japanese_and_english(self):
        self.assertTrue(
            self.denies(create_command(GOOD_BODY, title="ci: CI を軽くする"))
        )
        self.assertTrue(self.denies(create_command(GOOD_BODY + "\n- CI を軽くする\n")))

    def test_denies_more_than_three_bullets(self):
        body = GOOD_BODY + "- 三つ目\n- 四つ目\n"
        self.assertTrue(self.denies(create_command(body)))

    def test_denies_a_trailing_full_stop_on_a_bullet(self):
        body = GOOD_BODY.replace("出力する", "出力する。")
        self.assertTrue(self.denies(create_command(body)))

    def test_allows_a_full_stop_in_prose(self):
        body = GOOD_BODY.replace("省く", "省く。")
        self.assertFalse(self.denies(create_command(body)))

    def test_denies_a_checklist(self):
        body = GOOD_BODY + "- [ ] 動作を確認した\n"
        self.assertTrue(self.denies(create_command(body)))

    def test_denies_parentheses_outside_code(self):
        for text in ("補足（理由）", "補足(理由)"):
            body = GOOD_BODY.replace("省く", text)
            self.assertTrue(self.denies(create_command(body)))

    def test_allows_parentheses_in_code(self):
        body = GOOD_BODY + "\n`run(all)`を使う\n```\nprint(1)\n```\n"
        self.assertFalse(self.denies(create_command(body)))

    def test_allows_a_markdown_link(self):
        body = GOOD_BODY + "\n[設計メモ](https://example.com/memo)を参照\n"
        self.assertFalse(self.denies(create_command(body)))

    def test_denies_an_inline_issue_number(self):
        for text in (
            "#30 の判定に任せる",
            "owner/repo#30 の判定に任せる",
            "https://github.com/owner/repo/pull/30 の判定に任せる",
        ):
            body = GOOD_BODY.replace("省く", text)
            self.assertTrue(self.denies(create_command(body)), text)

    def test_allows_reference_lines(self):
        body = GOOD_BODY + "\n前提は以下で対応済み。\n→ PR #34\n"
        self.assertFalse(self.denies(create_command(body)))
        body = GOOD_BODY.replace("close #12", "Refs owner/repo#12")
        self.assertFalse(self.denies(create_command(body)))

    def test_denies_a_body_that_cannot_be_read_from_the_command(self):
        for command in (
            'gh pr create --title "ci: 軽くする" --body-file body.md',
            'gh pr create --title "ci: 軽くする" --body-file -',
            'gh pr create --title "ci: 軽くする" --body "$(cat body.md)"',
            'gh pr create --title "ci: 軽くする" --body "$BODY"',
            "gh pr edit 1 --body-file body.md",
        ):
            self.assertTrue(self.denies(command), command)

    def test_reads_a_heredoc_passed_to_the_body_file_flag(self):
        command = (
            "gh pr create --title \"ci: 軽くする\" --body-file - <<'EOF'\n"
            + GOOD_BODY
            + "- 補足（理由）\nEOF\n"
        )
        self.assertTrue(self.denies(command))

    def test_leaves_a_title_that_the_shell_expands(self):
        for title in ("$title", "ci: $summary", "`make title`"):
            command = f'gh pr create --title "{title}" --body "補足"'
            self.assertFalse(self.denies(command), title)

    def test_reads_single_quoted_values_with_code_spans(self):
        command = "gh pr create --title 'ci: `CI`を軽くする' --body '補足（理由）`CI`'"
        self.assertTrue(self.denies(command))

    def test_checks_every_list_marker(self):
        for marker in ("*", "+", "1."):
            body = "close #12\n\n背景を述べる\n\n" + "".join(
                f"{marker} 項目{n}。\n" for n in range(4)
            )
            self.assertTrue(self.denies(create_command(body)), marker)

    def test_checks_a_nested_bullet_and_a_star_checklist(self):
        body = GOOD_BODY + "  - 入れ子の項目。\n"
        self.assertTrue(self.denies(create_command(body)))
        body = GOOD_BODY + "* [x] 動作を確認した\n"
        self.assertTrue(self.denies(create_command(body)))

    def test_checks_a_literal_body(self):
        command = 'gh pr create --title "ci: 軽くする" --body "補足（理由）"'
        self.assertTrue(self.denies(command))

    def test_checks_edits_that_touch_the_title_or_body(self):
        command = 'gh pr edit 1 --title "軽くする"'
        self.assertTrue(self.denies(command))

    def test_finds_the_command_inside_a_chain(self):
        command = "git push -u origin HEAD && " + create_command(
            GOOD_BODY + "- 補足（理由）\n"
        )
        self.assertTrue(self.denies(command))


if __name__ == "__main__":
    unittest.main()
