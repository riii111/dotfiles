import fcntl
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/cloud-setup.sh"
# The refresh locks with util-linux flock, which the cloud image has and macOS lacks.
needs_flock = unittest.skipUnless(shutil.which("flock"), "flock is not installed")


class CloudSetupTest(unittest.TestCase):
    def setUp(self):
        home = tempfile.TemporaryDirectory()
        self.addCleanup(home.cleanup)
        self.home = Path(home.name)
        # Stands in for the agent-hooks build, which needs Linux x86_64. It reads the event as the real one does,
        # since exiting first would fail the setup's pipe into it.
        self.installer = self.home / "fake-install-agent-hooks.sh"
        self.installer.write_text(
            'printf "#!/bin/sh\\ncat >/dev/null\\n" > "$1/agent-hooks" && chmod +x "$1/agent-hooks"\n'
        )

    def run_setup(self, piped=False, **env):
        subprocess.run(
            ["bash"] if piped else ["bash", str(SCRIPT)],
            stdin=SCRIPT.open() if piped else None,
            cwd=self.home,
            env={
                "PATH": os.environ["PATH"],
                "HOME": str(self.home),
                "GIT_CONFIG_NOSYSTEM": "1",
                "AGENT_HOOKS_INSTALLER": str(self.installer),
                **env,
            },
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads((self.home / ".claude/settings.json").read_text())

    def post_commands(self, settings):
        return [
            hook["command"].rsplit("/", 1)[-1]
            for group in settings["hooks"]["PostToolUse"]
            for hook in group["hooks"]
        ]

    def commands(self, settings):
        return {
            group["matcher"]: [
                (hook["command"].rsplit("/", 1)[-1], hook["timeout"])
                for hook in group["hooks"]
            ]
            for group in settings["hooks"]["PreToolUse"]
        }

    def test_a_first_run_installs_the_hooks_skills_and_rules(self):
        settings = self.run_setup(PR_LANGUAGE="ja")

        # No --steer-tools, as the image lacks fd and bat; the safety rules need no flag.
        self.assertEqual(
            self.commands(settings),
            {"^(Bash|mcp__.*)$": [("agent-hooks pre-tool-use", 30)]},
        )
        self.assertEqual(self.post_commands(settings), ["agent-hooks pr-footer-reset"])
        self.assertEqual(
            [
                hook["command"].rsplit("/", 1)[-1]
                for group in settings["hooks"]["UserPromptSubmit"]
                for hook in group["hooks"]
            ],
            ["agent-hooks reply-reminder"],
        )
        skills = self.home / ".codex/skills"
        for name in (
            "ai-code-review",
            "code-review",
            "task-review-cycle",
            "task-worker",
        ):
            with self.subTest(name=name):
                self.assertEqual(
                    (skills / name / "SKILL.md").read_text(),
                    (ROOT / "dot_codex/skills" / name / "SKILL.md").read_text(),
                )
        self.assertTrue(
            (skills / "task-review-cycle/references/reply-Cloud.md").exists()
        )
        for name in ("task-orchestration", "task-worker", "pr-watch-link"):
            with self.subTest(claude=name):
                link = self.home / ".claude/skills" / name
                self.assertEqual(link.resolve(), (skills / name).resolve())
                self.assertTrue((link / "SKILL.md").exists())
        self.assertEqual(
            json.loads((self.home / ".config/harnexus/task.json").read_text()),
            {
                "templates": {
                    "worker": f"{skills}/task-session-launch/references/worker.md",
                    "reviewer": f"{skills}/task-review-cycle/references/reviewer.md",
                }
            },
        )
        self.assertIs(settings["includeCoAuthoredBy"], False)
        self.assertIs(settings["attribution"], False)
        self.assertEqual(
            settings["permissions"]["allow"], ["Bash(git push --force-with-lease *)"]
        )
        memory = (self.home / ".claude/CLAUDE.md").read_text()
        self.assertTrue(
            memory.startswith((ROOT / ".chezmoitemplates/agents-common.md").read_text())
        )
        self.assertIn("Co-Authored-By", memory)
        language = subprocess.run(
            ["git", "config", "--global", "--get", "pr.language"],
            env={"PATH": os.environ["PATH"], "HOME": str(self.home)},
            capture_output=True,
            text=True,
            check=True,
        )
        self.assertEqual(language.stdout.strip(), "ja")

    def test_a_failed_first_taskctl_build_still_installs_the_rest(self):
        settings = self.run_setup(
            HARNEXUS_TASK="1",
            HARNEXUS_TASK_PREFIX=str(self.home / "bin"),
            HARNEXUS_CREW_REPO=str(self.home / "missing"),
        )

        self.assertEqual(len(settings["hooks"]["PreToolUse"]), 1)
        self.assertTrue((self.home / ".config/harnexus/task.json").exists())
        self.assertTrue((self.home / ".codex/skills/task-worker/SKILL.md").exists())

    def test_writes_the_codex_login_at_session_start_once(self):
        settings = self.run_setup()
        self.run_setup()
        (start,) = settings["hooks"]["SessionStart"]
        (hook,) = [h for h in start["hooks"] if "codex-auth" in h["command"]]
        login = '{"auth_mode":"chatgpt"}'
        env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "CODEX_AUTH_B64": __import__("base64").b64encode(login.encode()).decode(),
        }

        ran = subprocess.run(
            hook["command"], shell=True, env=env, capture_output=True, text=True
        )

        auth = self.home / ".codex/auth.json"
        self.assertEqual([ran.returncode, ran.stdout, ran.stderr], [0, "", ""])
        self.assertEqual(auth.read_text(), login)
        self.assertEqual(auth.stat().st_mode & 0o777, 0o600)
        auth.write_text("kept")
        subprocess.run(hook["command"], shell=True, env=env, check=True)
        self.assertEqual(auth.read_text(), "kept")
        settings = json.loads((self.home / ".claude/settings.json").read_text())
        self.assertEqual(len(settings["hooks"]["SessionStart"]), 1)

    def refresh(self):
        subprocess.run(
            ["bash", str(self.home / ".claude/hooks/cloud-refresh.sh")],
            env={
                "PATH": os.environ["PATH"],
                "HOME": str(self.home),
                "GIT_CONFIG_NOSYSTEM": "1",
                "AGENT_HOOKS_INSTALLER": str(self.installer),
                "CLOUD_REFRESH_FOREGROUND": "1",
            },
            check=True,
            capture_output=True,
        )

    def dotfiles_repo(self, name):
        repo = self.home / name
        files = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files", "-co", "--exclude-standard", "-z"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.split("\0")
        for file in filter(None, files):
            if (ROOT / file).is_file():
                (repo / file).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / file, repo / file)
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        self.commit(repo, "worker", "dotfiles")
        return repo

    def commit(self, repo, skill, text):
        (repo / f"dot_codex/skills/task-{skill}/SKILL.md").write_text(text)
        for args in (["add", "-A"], ["commit", "-q", "-m", text]):
            subprocess.run(
                ["git", "-C", str(repo), "-c", "user.name=T", "-c", "user.email=t@e"]
                + args,
                check=True,
            )

    @needs_flock
    def test_runs_itself_again_from_the_latest_dotfiles_at_session_start(self):
        repo = self.dotfiles_repo("dotfiles")
        settings = self.run_setup(DOTFILES_REPO=str(repo))
        (start,) = settings["hooks"]["SessionStart"]
        (hook,) = [h for h in start["hooks"] if "cloud-refresh" in h["command"]]
        skill = self.home / ".codex/skills/task-worker/SKILL.md"
        stale = skill.parent / "stale.md"

        for version in ("dotfiles", "dotfiles", "updated"):
            with self.subTest(version=version):
                if version == "updated":
                    self.commit(repo, "worker", "updated")
                stale.write_text("removed upstream")
                subprocess.run(
                    hook["command"],
                    shell=True,
                    env={
                        "PATH": os.environ["PATH"],
                        "HOME": str(self.home),
                        "GIT_CONFIG_NOSYSTEM": "1",
                        "AGENT_HOOKS_INSTALLER": str(self.installer),
                        "CLOUD_REFRESH_FOREGROUND": "1",
                    },
                    check=True,
                    capture_output=True,
                )

                self.assertFalse(stale.exists())
                self.assertEqual(skill.read_text(), version)

        # Setting up again from another repository points the refresh at it.
        second = self.home / "second"
        subprocess.run(["git", "clone", "-q", str(repo), str(second)], check=True)
        self.commit(second, "worker", "second")
        self.run_setup(DOTFILES_REPO=str(second))
        self.refresh()
        self.assertEqual(skill.read_text(), "second")

    @needs_flock
    def test_skips_a_refresh_while_another_runs(self):
        self.run_setup(DOTFILES_REPO=str(self.dotfiles_repo("dotfiles")))
        stale = self.home / ".codex/skills/task-worker/stale.md"
        stale.write_text("kept while another refresh runs")

        with open(self.home / ".cache/cloud-setup/refresh.flock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.refresh()

        self.assertTrue(stale.exists())

    @needs_flock
    def test_waits_for_a_refresh_of_an_earlier_version_to_end(self):
        self.run_setup(DOTFILES_REPO=str(self.dotfiles_repo("dotfiles")))
        legacy = self.home / ".cache/cloud-setup/refresh.lock"
        stale = self.home / ".codex/skills/task-worker/stale.md"
        dead = subprocess.Popen(["true"])
        dead.wait()
        # (pid written, lock age in seconds, whether the old refresh still runs)
        for name, pid, age, running in (
            ("live pid", os.getpid(), 0, True),
            ("pid not written yet", None, 0, True),
            ("dead pid", dead.pid, 0, False),
            ("no pid for over a minute", None, 120, False),
        ):
            with self.subTest(name):
                shutil.rmtree(legacy, ignore_errors=True)
                legacy.mkdir()
                if pid is not None:
                    (legacy / "pid").write_text(str(pid))
                os.utime(legacy, (time.time() - age,) * 2)
                stale.write_text("removed upstream")

                self.refresh()

                self.assertEqual(stale.exists(), running)
                self.assertEqual(legacy.exists(), running)

    @needs_flock
    def test_a_refresh_that_ended_early_does_not_stop_the_next(self):
        self.run_setup(DOTFILES_REPO=str(self.dotfiles_repo("dotfiles")))
        state = self.home / ".cache/cloud-setup"
        # What an interrupted refresh leaves.
        (state / "refresh.flock").touch()
        stale = self.home / ".codex/skills/task-worker/stale.md"
        stale.write_text("removed upstream")

        self.refresh()
        self.refresh()

        self.assertFalse(stale.exists())

    def source_repo(self, name, files):
        repo = self.home / name
        for path, text in files.items():
            (repo / path).parent.mkdir(parents=True, exist_ok=True)
            (repo / path).write_text(text)
        subprocess.run(["git", "init", "-q", str(repo)], check=True)
        for args in (["add", "-A"], ["commit", "-q", "-m", name]):
            subprocess.run(
                ["git", "-C", str(repo), "-c", "user.name=T", "-c", "user.email=t@e"]
                + args,
                check=True,
            )
        return repo, subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    # Fills the worker template task.json names, as the real check renders every template.
    TASKCTL = (
        "#!/bin/sh\n"
        'case $1 in check) w=$(sed -n \'s/.*"worker": "\\(.*\\)".*/\\1/p\' '
        '"${XDG_CONFIG_HOME:-$HOME/.config}/harnexus/task.json") && test -f "$w" ;; esac\n'
    )

    def crew_repo(self, name="crew", crew=TASKCTL):
        installer = (
            "set -e\n"
            "while [ $# -gt 0 ]; do case $1 in\n"
            "  --prefix) prefix=$2; shift 2 ;; --repo) repo=$2; shift 2 ;;\n"
            "  --rev) rev=$2; shift 2 ;; --bun) shift 2 ;; *) exit 2 ;;\n"
            "esac; done\n"
            'new=$(mktemp); cp "$repo/harnexus-crew" "$new"; chmod +x "$new"; "$new" check\n'
            'printf "%s\\n" "$rev" >"$prefix/installer.log"\n'
            'mv "$new" "$prefix/harnexus-crew"\n'
        )
        return self.source_repo(
            name, {"scripts/install.sh": installer, "harnexus-crew": crew}
        )

    def run_task_setup(self, check=True, **env):
        prefix = self.home / "bin"
        prefix.mkdir(exist_ok=True)
        ran = subprocess.run(
            ["bash", str(SCRIPT)],
            env={
                "PATH": os.environ["PATH"],
                "HOME": str(self.home),
                "GIT_CONFIG_NOSYSTEM": "1",
                "AGENT_HOOKS_INSTALLER": str(self.installer),
                "HARNEXUS_TASK": "1",
                "HARNEXUS_TASK_PREFIX": str(prefix),
                **env,
            },
            capture_output=True,
            text=True,
        )
        if check:
            self.assertEqual(ran.returncode, 0, ran.stderr)
        return prefix, ran

    def test_installs_harnexus_crew(self):
        repo, rev = self.crew_repo()
        prefix, _ = self.run_task_setup(
            HARNEXUS_CREW_REPO=str(repo), HARNEXUS_CREW_REV=rev
        )

        self.assertEqual((prefix / "installer.log").read_text().strip(), rev)
        self.assertEqual((prefix / ".harnexus-crew.commit").read_text().strip(), rev)
        self.assertTrue((self.home / ".codex/skills/task-worker/SKILL.md").exists())

    def test_a_crew_that_fails_keeps_the_previous_set(self):
        repo, rev = self.crew_repo()
        prefix, _ = self.run_task_setup(
            HARNEXUS_CREW_REPO=str(repo), HARNEXUS_CREW_REV=rev
        )
        broken, broken_rev = self.crew_repo("broken", crew="#!/bin/sh\nexit 1\n")
        skill = self.home / ".codex/skills/task-worker"
        (skill / "kept.md").write_text("the set in use")
        working = (prefix / "harnexus-crew").read_text()

        for name, env, installed in (
            (
                "check fails",
                {"HARNEXUS_CREW_REPO": str(broken), "HARNEXUS_CREW_REV": broken_rev},
                working,
            ),
            (
                "not a full commit",
                {"HARNEXUS_CREW_REPO": str(repo), "HARNEXUS_CREW_REV": rev[:12]},
                working,
            ),
            (
                "the installed one cannot fill the new templates",
                {"HARNEXUS_CREW_REPO": str(repo), "HARNEXUS_CREW_REV": rev},
                "#!/bin/sh\nexit 1\n",
            ),
        ):
            with self.subTest(name):
                (prefix / "harnexus-crew").write_text(installed)
                _, ran = self.run_task_setup(**env)

                self.assertIn(
                    "previous skills, task.json and task CLI stay", ran.stderr
                )
                self.assertTrue((skill / "kept.md").exists())
                self.assertEqual(
                    (prefix / ".harnexus-crew.commit").read_text().strip(), rev
                )

    def test_clones_the_dotfiles_when_piped_into_bash(self):
        settings = self.run_setup(
            piped=True, DOTFILES_REPO=str(self.dotfiles_repo("dotfiles"))
        )

        self.assertEqual(len(settings["hooks"]["PreToolUse"]), 1)
        self.assertTrue((self.home / ".claude/hooks/codex-auth.sh").exists())

    def test_running_again_keeps_other_hooks_and_adds_nothing_twice(self):
        own = {
            "type": "command",
            "command": f"python3 {self.home}/.claude/hooks/my-check.py",
        }
        settings = self.run_setup()
        settings["permissions"] = {"deny": ["SearchPlugins"]}
        settings["hooks"]["PreToolUse"].insert(0, {"matcher": "Write", "hooks": [own]})
        # A hook of the user's own added to a group this script installed.
        settings["hooks"]["PreToolUse"][-1]["hooks"].append(own)
        (self.home / ".claude/settings.json").write_text(json.dumps(settings))

        settings = self.run_setup()

        self.assertEqual(
            settings["permissions"],
            {
                "deny": ["SearchPlugins"],
                "allow": ["Bash(git push --force-with-lease *)"],
            },
        )
        groups = settings["hooks"]["PreToolUse"]
        self.assertEqual(
            [group["matcher"] for group in groups],
            ["Write", "^(Bash|mcp__.*)$", "^(Bash|mcp__.*)$"],
        )
        self.assertEqual(groups[0]["hooks"], [own])
        self.assertEqual(groups[1]["hooks"], [own])
        self.assertEqual(sum(len(group["hooks"]) for group in groups), 3)

    GUARDS = (
        "github-comment-check",
        "git-force-check",
        "pr-format-check",
        "pr-state-check",
    )

    def install_python_guards(self):
        hooks = self.home / ".claude/hooks"
        hooks.mkdir(parents=True, exist_ok=True)
        for name in (*self.GUARDS, "pr-footer-reset"):
            (hooks / f"{name}.py").write_text("")
        (self.home / ".claude/settings.json").write_text(
            json.dumps(
                {
                    "hooks": {
                        "PreToolUse": [
                            {
                                "matcher": "Bash",
                                "hooks": [
                                    {
                                        "type": "command",
                                        "command": f"python3 {hooks}/{name}.py",
                                    }
                                    for name in self.GUARDS
                                ],
                            }
                        ]
                    }
                }
            )
        )
        return hooks

    def guard_commands(self, settings):
        return sorted(
            {
                hook["command"].rsplit("/", 1)[-1]
                for group in settings["hooks"]["PreToolUse"]
                for hook in group["hooks"]
            }
        )

    def failing_installer(self):
        installer = self.home / "failing-install-agent-hooks.sh"
        installer.write_text("exit 1\n")
        return str(installer)

    def test_a_built_agent_hooks_replaces_the_python_guards(self):
        hooks = self.install_python_guards()

        settings = self.run_setup()

        self.assertEqual(self.guard_commands(settings), ["agent-hooks pre-tool-use"])
        self.assertEqual(self.post_commands(settings), ["agent-hooks pr-footer-reset"])
        for name in (*self.GUARDS, "pr-footer-reset"):
            self.assertFalse((hooks / f"{name}.py").exists(), name)

    def test_a_failed_build_keeps_the_python_guards(self):
        hooks = self.install_python_guards()

        settings = self.run_setup(AGENT_HOOKS_INSTALLER=self.failing_installer())

        self.assertEqual(
            self.guard_commands(settings),
            sorted(f"{name}.py" for name in self.GUARDS),
        )
        self.assertEqual(self.post_commands(settings), ["pr-footer-reset.py"])
        for name in (*self.GUARDS, "pr-footer-reset"):
            self.assertTrue((hooks / f"{name}.py").exists(), name)

    def test_a_failed_build_keeps_a_previously_built_agent_hooks(self):
        hooks = self.home / ".claude/hooks"
        hooks.mkdir(parents=True)
        # One built before pre-tool-use fails on its name, so the separate checks are installed.
        (hooks / "agent-hooks").write_text(
            '#!/bin/sh\ncat >/dev/null\ncase "$1" in pre-tool-use) exit 1 ;; esac\n'
        )
        (hooks / "agent-hooks").chmod(0o755)

        settings = self.run_setup(AGENT_HOOKS_INSTALLER=self.failing_installer())
        self.assertEqual(
            self.guard_commands(settings),
            sorted(
                f"agent-hooks {name}" for name in (*self.GUARDS, "comment-review-check")
            ),
        )

        # A build that has pre-tool-use replaces them all.
        settings = self.run_setup()
        self.assertEqual(
            self.commands(settings),
            {"^(Bash|mcp__.*)$": [("agent-hooks pre-tool-use", 30)]},
        )

    def test_a_guard_the_previous_agent_hooks_lacks_keeps_its_python_copy(self):
        hooks = self.install_python_guards()
        # An agent-hooks built before the PR checks moved fails on their names.
        (hooks / "agent-hooks").write_text(
            '#!/bin/sh\ncase "$1" in pr-* | pre-tool-use) exit 1 ;; esac\n'
        )
        (hooks / "agent-hooks").chmod(0o755)

        settings = self.run_setup(AGENT_HOOKS_INSTALLER=self.failing_installer())

        self.assertEqual(
            self.guard_commands(settings),
            [
                "agent-hooks comment-review-check",
                "agent-hooks git-force-check",
                "agent-hooks github-comment-check",
                "pr-format-check.py",
                "pr-state-check.py",
            ],
        )
        self.assertFalse((hooks / "git-force-check.py").exists())
        self.assertTrue((hooks / "pr-state-check.py").exists())

    def test_a_failed_first_build_installs_the_rest_and_fails(self):
        ran = subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.home,
            env={
                "PATH": os.environ["PATH"],
                "HOME": str(self.home),
                "GIT_CONFIG_NOSYSTEM": "1",
                "AGENT_HOOKS_INSTALLER": self.failing_installer(),
            },
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(ran.returncode, 0)
        self.assertIn("guards are not installed", ran.stderr)
        settings = json.loads((self.home / ".claude/settings.json").read_text())
        self.assertEqual(settings["hooks"]["PreToolUse"], [])
        self.assertEqual(settings["hooks"]["PostToolUse"], [])
        self.assertEqual(settings["hooks"]["UserPromptSubmit"], [])
        self.assertTrue((self.home / ".codex/skills/task-worker/SKILL.md").exists())


if __name__ == "__main__":
    unittest.main()
