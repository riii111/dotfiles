import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "bin/executable_gh.tmpl"
WORK_DATA = ROOT / "tests/chezmoi/work.toml"
PERSONAL = "personal"
WORK = "work"


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
        for path in (self.wrapper_dir, self.real_dir):
            path.mkdir(parents=True)
        for account in (PERSONAL, WORK):
            folder = self.account_dir(account)
            folder.mkdir(parents=True)
            (folder / "hosts.yml").write_text("github.com:\n")

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
        real.write_text(
            "#!/bin/sh\n"
            'case "$*" in *--watch*) sleep 2 ;; esac\n'
            f'printf "%s %s\\n" "${{GH_CONFIG_DIR:--}}" "$*" >> "{self.log}"\n'
        )
        real.chmod(0o755)

    def account_dir(self, account):
        return self.home / ".config/gh-accounts" / account

    def gh_command(self, *args):
        return [str(self.wrapper_dir / "gh"), *args]

    def gh_env(self):
        return {
            "HOME": str(self.home),
            "TMPDIR": str(self.root),
            "GIT_CEILING_DIRECTORIES": str(self.root),
            "PATH": os.pathsep.join(
                (str(self.wrapper_dir), str(self.real_dir), "/usr/bin", "/bin")
            ),
        }

    def run_gh(self, *args, cwd=None, env=None):
        subprocess.run(
            self.gh_command(*args),
            cwd=cwd or self.home,
            env={**self.gh_env(), **(env or {})},
            capture_output=True,
            check=True,
        )
        return self.log.read_text().splitlines()

    def logged(self, account, *args):
        config_dir = self.account_dir(account) if account else "-"
        return f"{config_dir} {' '.join(args)}"

    def assert_runs_as(self, account, *args, cwd=None, env=None):
        self.assertEqual(
            self.run_gh(*args, cwd=cwd, env=env), [self.logged(account, *args)]
        )

    def repository(self, origin, path="repo"):
        repo = self.root / path
        repo.mkdir(parents=True)
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        subprocess.run(
            ["git", "-C", str(repo), "remote", "add", "origin", origin], check=True
        )
        return repo

    def test_repository_arguments_select_the_account(self):
        for args, env, account in (
            (("pr", "view", "1", "-R", "work-org/app"), None, WORK),
            (("pr", "view", "1", "-R=work-org/app"), None, WORK),
            (("pr", "view", "1", "-RWork-Org/app"), None, WORK),
            (("pr", "view", "1", "--repo", "github.com/work-org/app"), None, WORK),
            (("pr", "view", "1", "--repo=riii111/dotfiles"), None, PERSONAL),
            (("pr", "view", "-R", "riii111/a", "-R", "work-org/a"), None, WORK),
            (("pr", "view", "1"), {"GH_REPO": "work-org/app"}, WORK),
            (("issue", "list", "-R", "someone/app"), None, None),
        ):
            with self.subTest(args=args, env=env):
                self.log.unlink(missing_ok=True)
                self.assert_runs_as(account, *args, env=env)

    def test_repository_flag_wins_over_urls_and_origin(self):
        repo = self.repository("git@github.com:riii111/dotfiles.git")
        url = "https://github.com/riii111/dotfiles/issues/1"
        for args in (
            ("pr", "create", "--body", f"Related {url}", "--repo", "work-org/app"),
            ("pr", "view", url, "-R", "work-org/app"),
        ):
            with self.subTest(args=args):
                self.log.unlink(missing_ok=True)
                self.assert_runs_as(WORK, *args, cwd=repo)

    def test_only_whole_github_urls_select_the_account(self):
        repo = self.repository("git@github.com:work-org/app.git")
        url = "https://github.com/riii111/dotfiles/pull/1"
        for args, account in (
            (("pr", "checkout", "-f", url), PERSONAL),
            (("pr", "view", "https://www.github.com/riii111/app/pull/1"), PERSONAL),
            (("issue", "close", "1", "--comment", f"text {url}"), WORK),
        ):
            with self.subTest(args=args):
                self.log.unlink(missing_ok=True)
                self.assert_runs_as(account, *args, cwd=repo)

    def test_origin_selects_the_account_outside_ghq(self):
        for origin, account in (
            ("git@github.com:work-org/app.git", WORK),
            ("git@github.com-riii111:riii111/dotfiles.git", PERSONAL),
            ("https://github.com/riii111/dotfiles.git", PERSONAL),
            ("ssh://git@github.com/work-org/app.git", WORK),
            ("https://github.com/someone/app.git", None),
        ):
            with self.subTest(origin=origin):
                self.log.unlink(missing_ok=True)
                repo = self.repository(origin, path=f"repos/{len(origin)}")
                self.assert_runs_as(account, "pr", "list", cwd=repo)

    def test_ghq_path_is_the_fallback(self):
        workspace = self.home / "ghq/github.com/work-org/app/sub"
        workspace.mkdir(parents=True)
        self.assert_runs_as(WORK, "pr", "list", cwd=workspace)

    def test_passes_through_without_choosing_an_account(self):
        repo = self.repository("git@github.com:work-org/app.git")
        for args, env, cwd in (
            (("pr", "list"), None, self.home),
            (("auth", "status"), None, repo),
            (("pr", "list"), {"GH_TOKEN": "from-outside"}, repo),
        ):
            with self.subTest(args=args, env=env):
                self.log.unlink(missing_ok=True)
                self.assert_runs_as(None, *args, cwd=cwd, env=env)

    def test_existing_config_dir_is_kept(self):
        repo = self.repository("git@github.com:work-org/app.git")
        outer = str(self.account_dir(PERSONAL))
        args = ("auth", "git-credential", "get")
        self.assertEqual(
            self.run_gh(*args, cwd=repo, env={"GH_CONFIG_DIR": outer}),
            [f"{outer} {' '.join(args)}"],
        )

    def test_missing_account_folder_keeps_the_active_account(self):
        shutil.rmtree(self.account_dir(WORK))
        self.assert_runs_as(None, "pr", "list", "-R", "work-org/app")

    def test_concurrent_calls_do_not_affect_each_other(self):
        watch = ("pr", "checks", "1", "--watch", "-R", "riii111/dotfiles")
        watcher = subprocess.Popen(
            self.gh_command(*watch),
            cwd=self.home,
            env=self.gh_env(),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.addCleanup(watcher.kill)
        other = ("pr", "list", "-R", "work-org/app")
        self.assertEqual(self.run_gh(*other), [self.logged(WORK, *other)])
        self.assertIsNone(watcher.poll())
        self.assertEqual(watcher.wait(timeout=10), 0)
        self.assertEqual(
            self.log.read_text().splitlines(),
            [self.logged(WORK, *other), self.logged(PERSONAL, *watch)],
        )
