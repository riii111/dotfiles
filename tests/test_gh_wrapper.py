import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "bin/executable_gh.tmpl"
WORK_DATA = ROOT / "tests/chezmoi/work.toml"
WORK_USER = "work-gh-user"


@unittest.skipUnless(
    shutil.which("chezmoi") and Path("/bin/zsh").exists(), "chezmoi or zsh missing"
)
class GhWrapperTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name).resolve()
        self.home = self.root / "home"
        self.wrapper_dir = self.root / "wrapper"
        self.real_dir = self.root / "real"
        self.log = self.root / "gh.log"
        for path in (self.home / ".config/gh", self.wrapper_dir, self.real_dir):
            path.mkdir(parents=True)
        (self.home / ".config/gh/hosts.yml").write_text(
            "github.com:\n    user: someone-else\n"
        )

        rendered = subprocess.run(
            [
                "chezmoi",
                "--config",
                str(WORK_DATA),
                "--source",
                str(ROOT),
                "--persistent-state",
                str(self.root / "chezmoistate.boltdb"),
                "execute-template",
                "--file",
                str(TEMPLATE),
            ],
            env={"PATH": os.environ["PATH"], "HOME": str(self.root)},
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=True,
        )
        wrapper = self.wrapper_dir / "gh"
        wrapper.write_bytes(rendered.stdout)
        wrapper.chmod(0o755)

        real = self.real_dir / "gh"
        real.write_text(f'#!/bin/sh\nprintf "%s\\n" "$*" >> "{self.log}"\n')
        real.chmod(0o755)

    def run_gh(self, *args, cwd=None):
        subprocess.run(
            [str(self.wrapper_dir / "gh"), *args],
            cwd=cwd or self.home,
            env={
                "HOME": str(self.home),
                "TMPDIR": str(self.root),
                "GIT_CEILING_DIRECTORIES": str(self.root),
                "PATH": os.pathsep.join(
                    (str(self.wrapper_dir), str(self.real_dir), "/usr/bin", "/bin")
                ),
            },
            capture_output=True,
            check=True,
        )
        return self.log.read_text().splitlines()

    def assert_switched_to(self, user, *args, cwd=None):
        command = " ".join(args)
        expected = [command]
        if user is not None:
            expected.insert(0, f"auth switch --hostname github.com --user {user}")
        self.assertEqual(self.run_gh(*args, cwd=cwd), expected)

    def repository(self, origin, path="repo"):
        repo = self.root / path
        repo.mkdir(parents=True)
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(
            ["git", "-C", str(repo), "remote", "add", "origin", origin], check=True
        )
        return repo

    def test_repository_arguments_select_the_owner(self):
        for args, user in (
            (("pr", "view", "1", "-R", "work-org/app"), WORK_USER),
            (("pr", "view", "1", "--repo", "github.com/work-org/app"), WORK_USER),
            (("pr", "view", "1", "--repo=riii111/dotfiles"), "riii111"),
            (("pr", "view", "1", "-RWork-Org/app"), WORK_USER),
            (("pr", "view", "https://github.com/work-org/app/pull/1"), WORK_USER),
            (("issue", "list", "-R", "someone/app"), None),
        ):
            with self.subTest(args=args):
                self.log.unlink(missing_ok=True)
                self.assert_switched_to(user, *args)

    def test_arguments_take_precedence_over_origin(self):
        repo = self.repository("git@github.com:riii111/dotfiles.git")
        self.assert_switched_to(WORK_USER, "pr", "list", "-R", "work-org/app", cwd=repo)

    def test_origin_selects_the_owner_outside_ghq(self):
        for origin, user in (
            ("git@github.com:work-org/app.git", WORK_USER),
            ("https://github.com/riii111/dotfiles.git", "riii111"),
            ("ssh://git@github.com/work-org/app.git", WORK_USER),
            ("https://github.com/someone/app.git", None),
        ):
            with self.subTest(origin=origin):
                self.log.unlink(missing_ok=True)
                repo = self.repository(origin, path=f"repos/{len(origin)}-{user}")
                self.assert_switched_to(user, "pr", "list", cwd=repo)

    def test_ghq_path_is_the_fallback(self):
        workspace = self.home / "ghq/github.com/work-org/app/sub"
        workspace.mkdir(parents=True)
        self.assert_switched_to(WORK_USER, "pr", "list", cwd=workspace)

    def test_unknown_location_keeps_the_active_account(self):
        self.assert_switched_to(None, "pr", "list")
