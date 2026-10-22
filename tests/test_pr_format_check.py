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
        self.use_language("ja")

    def use_language(self, language):
        patcher = mock.patch.object(self.check, "read_language", return_value=language)
        patcher.start()
        self.addCleanup(patcher.stop)

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

    def test_issue_reference_requires_closing_keyword(self):
        self.assertTrue(
            self.denies(create_command(GOOD_BODY.replace("close #12", "Refs #12")))
        )
        self.assertFalse(
            self.denies(create_command(GOOD_BODY.replace("close #12", "Close #12")))
        )
        self.assertFalse(
            self.denies(create_command(GOOD_BODY.replace("close #12", "")))
        )

    def test_accepts_a_conforming_pr(self):
        self.assertFalse(self.denies(create_command(GOOD_BODY)))

    def test_ignores_other_commands(self):
        self.assertFalse(self.denies("git status"))
        self.assertFalse(self.denies("gh pr edit 1 --add-label bug"))

    def test_survives_unparsable_input(self):
        output = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO("not json")), redirect_stdout(output):
            self.assertEqual(self.check.main(), 0)
        self.assertEqual(output.getvalue(), "")

    def test_denies_a_body_that_cannot_be_read_from_the_command(self):
        for command in (
            'gh pr create --title "ci: 軽くする" --body-file body.md',
            'gh pr create --title "ci: 軽くする" --body "$BODY"',
        ):
            self.assertTrue(self.denies(command), command)

    def test_reads_a_heredoc_passed_to_the_body_file_flag(self):
        command = (
            "gh pr create --title \"ci: 軽くする\" --body-file - <<'EOF'\n"
            + GOOD_BODY
            + "- 補足（理由）\nEOF\n"
        )
        self.assertTrue(self.denies(command))

    def test_checks_edits_that_touch_the_title_or_body(self):
        command = 'gh pr edit 1 --title "軽くする"'
        self.assertTrue(self.denies(command))

    def test_finds_the_command_inside_a_chain(self):
        command = "git push -u origin HEAD && " + create_command(
            GOOD_BODY + "- 補足（理由）\n"
        )
        self.assertTrue(self.denies(command))

    def test_denies_when_the_language_is_not_configured(self):
        for language in (None, "fr"):
            self.use_language(language)
            self.assertTrue(self.denies(create_command(GOOD_BODY)), language)

    def test_denies_a_pr_in_the_other_language(self):
        english_title = "ci: trim test logs"
        self.assertTrue(self.denies(create_command(GOOD_BODY, title=english_title)))
        self.use_language("en")
        self.assertTrue(self.denies(create_command(GOOD_BODY)))

    def test_accepts_an_english_pr_when_configured(self):
        self.use_language("en")
        body = "close #12\n\nPassing tests flood the log and hide failures.\n"
        self.assertFalse(self.denies(create_command(body, title="ci: trim test logs")))

    def test_denies_broken_japanese_sentences(self):
        for tail in (
            "省く。守る対象は保存期間とバケット名。",
            "省くので、集約すれば、確認は不要になる。",
        ):
            body = GOOD_BODY.replace("省く", tail)
            self.assertTrue(self.denies(create_command(body)), tail)

    def test_accepts_short_japanese_sentences_and_english(self):
        body = GOOD_BODY.replace("省く", "省く。確認は不要になる。")
        self.assertFalse(self.denies(create_command(body)))
        self.use_language("en")
        body = "close #12\n\nThe log is noisy. Trimming it makes failures visible.\n"
        self.assertFalse(self.denies(create_command(body, title="ci: trim logs")))


if __name__ == "__main__":
    unittest.main()
