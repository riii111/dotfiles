import importlib.machinery
import importlib.util
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "dot_claude" / "hooks" / "executable_git-force-check.py"


def load_check():
    loader = importlib.machinery.SourceFileLoader("git_force_check", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GitForceCheckTest(unittest.TestCase):
    def setUp(self):
        self.check = load_check()

    def decision(self, command, deny_force_push=False):
        result = self.check.decide(command, deny_force_push)
        return result[0] if result else None

    def test_force_with_lease_passes(self):
        for command in [
            "git push --force-with-lease",
            "git push --force-with-lease=feat/x origin HEAD:feat/x",
            "git push --force-with-lease --force-if-includes origin feat/x",
            "cd repo && git push --force-with-lease 2>&1",
        ]:
            with self.subTest(command=command):
                self.assertIsNone(self.decision(command, deny_force_push=True))

    def test_forced_push_asks_or_is_denied(self):
        for command in [
            "git push --force",
            "git push origin feat/x --force",
            "git push -f origin feat/x",
            "git push -uf origin feat/x",
            "git push origin +feat/x",
            "git push --force-with-lease origin +feat/x",
            "git -C repo push origin +HEAD:feat/x",
            "git status && git push -f",
            "git status\ngit push origin +feat/x",
        ]:
            with self.subTest(command=command):
                self.assertEqual(self.decision(command), "ask")
                self.assertEqual(self.decision(command, deny_force_push=True), "deny")

    def test_normal_push_passes(self):
        for command in [
            "git push",
            "git push -u origin feat/x",
            "git push -o ci.skip origin feat/x",
            "git push origin -- feat/x",
            'git commit -m "allow git push -f" && git push',
        ]:
            with self.subTest(command=command):
                self.assertIsNone(self.decision(command, deny_force_push=True))

    def test_forced_add_is_denied(self):
        for command in [
            "git add -f x",
            "git add --force x",
            "git add --for x",
            "git add -Af",
        ]:
            with self.subTest(command=command):
                self.assertEqual(self.decision(command), "deny")

    def test_add_ignores_force_in_later_lines(self):
        for command in [
            "git add x\ngit push --force-with-lease",
            "git add x && git commit -m 'use --force'",
            "git add -- -f",
        ]:
            with self.subTest(command=command):
                self.assertIsNone(self.decision(command))


if __name__ == "__main__":
    unittest.main()
