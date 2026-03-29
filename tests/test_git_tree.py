import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "bin" / "executable_git-tree"


class GitTreeTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.repo = Path(self.tempdir.name)
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Test User")
        self.git("config", "user.email", "test@example.com")
        self.commit_file("root.txt", "root\n", "root")

    def tearDown(self):
        self.tempdir.cleanup()

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args],
            cwd=self.repo,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()

    def commit_file(self, name, content, message, append=False):
        path = self.repo / name
        mode = "a" if append else "w"
        with path.open(mode, encoding="utf-8") as f:
            f.write(content)
        self.git("add", name)
        self.git("commit", "-m", message)

    def run_tree(self):
        return subprocess.check_output(
            [str(SCRIPT)],
            cwd=self.repo,
            text=True,
            stderr=subprocess.DEVNULL,
        )

    def test_keeps_advanced_parent_as_base(self):
        self.git("checkout", "-b", "parent")
        self.commit_file("parent.txt", "parent-1\n", "parent-1")

        self.git("checkout", "-b", "child")
        self.commit_file("child.txt", "child-1\n", "child-1")
        self.commit_file("child.txt", "child-2\n", "child-2", append=True)

        self.git("checkout", "parent")
        self.commit_file("parent.txt", "parent-2\n", "parent-2", append=True)

        self.git("checkout", "child")
        output = self.run_tree()

        self.assertIn("  main", output)
        self.assertIn("  └── parent (+2)", output)
        self.assertIn("      └── child (+2) ★", output)

    def test_keeps_original_parent_after_merging_main(self):
        self.git("checkout", "-b", "parent")
        self.commit_file("parent.txt", "parent-1\n", "parent-1")

        self.git("checkout", "-b", "child")
        self.commit_file("child.txt", "child-1\n", "child-1")

        self.git("checkout", "main")
        self.commit_file("main.txt", "main-1\n", "main-1")

        self.git("checkout", "child")
        self.git("merge", "--no-ff", "main", "-m", "merge-main")

        self.git("checkout", "parent")
        self.commit_file("parent.txt", "parent-2\n", "parent-2", append=True)

        self.git("checkout", "child")
        output = self.run_tree()
        lines = [line for line in output.splitlines() if line]

        self.assertIn("  main", lines)
        self.assertIn("  └── parent (+2)", lines)
        self.assertIn("      └── child (+3) ★", lines)
        self.assertNotIn("  ├── child (+3) ★", lines)
        self.assertNotIn("  └── child (+3) ★", lines)


if __name__ == "__main__":
    unittest.main()
