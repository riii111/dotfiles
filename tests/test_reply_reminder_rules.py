import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REMINDER = ROOT / "dot-tools/reply_reminder/reply_reminder.mbt"
RULES = ROOT / ".chezmoitemplates/agents-common.md"


def sections(markdown):
    """Maps each `## ` heading name, without a `: subtitle`, to its body."""
    table = {}
    name = None
    for line in markdown.splitlines():
        if line.startswith("## "):
            name = line[3:].split(":", 1)[0].strip()
            table[name] = ""
        elif name is not None:
            table[name] += line + "\n"
    return table


class ReplyReminderRulesTest(unittest.TestCase):
    """The reminder quotes CLAUDE.md, which nothing else keeps it in sync with."""

    def test_named_sections_and_quoted_rules_exist(self):
        source = REMINDER.read_text()
        table = sections(RULES.read_text())
        names = re.findall(r"「([^」]+)」", source)
        self.assertTrue(names)
        for name in names:
            with self.subTest(section=name):
                self.assertIn(name, table)
        # The quoted rules follow a line naming the section they come from.
        quote = re.search(
            r"#\|.*「([^」]+)」から再掲する。\n((?:\s*#\|- .*\n)+)", source
        )
        self.assertIsNotNone(quote)
        section, lines = quote.groups()
        rules = re.findall(r"#\|- (.*)", lines)
        self.assertTrue(rules)
        for rule in rules:
            with self.subTest(rule=rule):
                self.assertIn(rule, table[section])


if __name__ == "__main__":
    unittest.main()
