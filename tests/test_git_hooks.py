import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HOOKS_SCRIPT = REPO_ROOT / "dot_git-hooks.zsh"
TEMPLATE_SOURCE_DIR = REPO_ROOT / "dot_git_hook_templates"


def chezmoi_target_name(source_name):
    return source_name.removeprefix("executable_")


@unittest.skipIf(shutil.which("zsh") is None, "zsh not found")
class GitHooksTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        root = Path(self.tempdir.name)
        self.home = root / "home"
        self.template_dir = self.home / ".git_hook_templates"
        self.template_dir.mkdir(parents=True)
        for source in TEMPLATE_SOURCE_DIR.iterdir():
            shutil.copy2(source, self.template_dir / chezmoi_target_name(source.name))
        self.repo = root / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q"], cwd=self.repo, check=True, env=self.env())

    def tearDown(self):
        self.tempdir.cleanup()

    def env(self):
        env = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith("GIT_")
        }
        env["HOME"] = str(self.home)
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        return env

    def run_zsh(self, command):
        return subprocess.run(
            ["zsh", "-f", "-c", f'source "$1" && {command}', "zsh", HOOKS_SCRIPT],
            cwd=self.repo,
            env=self.env(),
            capture_output=True,
            text=True,
        )

    def listed_templates(self):
        result = self.run_zsh("setup-git-hooks")
        self.assertEqual(result.returncode, 1, result.stderr)
        return [
            line.strip() for line in result.stdout.splitlines() if line.startswith("  ")
        ]

    def test_guidance_lists_every_installed_template(self):
        expected = sorted(
            chezmoi_target_name(path.name) for path in TEMPLATE_SOURCE_DIR.iterdir()
        )
        self.assertEqual(sorted(self.listed_templates()), expected)

    def test_each_listed_template_can_be_installed(self):
        hook = self.repo / ".git" / "hooks" / "pre-commit"
        for template in self.listed_templates():
            with self.subTest(template=template):
                result = self.run_zsh(f"setup-git-hooks {template}")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertTrue(hook.is_symlink())
                self.assertEqual(Path(os.readlink(hook)), self.template_dir / template)
                self.assertTrue(os.access(hook, os.X_OK))


if __name__ == "__main__":
    unittest.main()
