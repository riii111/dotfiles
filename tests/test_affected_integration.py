import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli


ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader(
    "affected_invoke", str(ROOT / "bin/executable_affected-agent")
)
spec = importlib.util.spec_from_loader(loader.name, loader)
affected = importlib.util.module_from_spec(spec)
loader.exec_module(affected)


class AgentInvocationTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.agent = self.home / "agent with spaces"
        patch = mock.patch.dict(
            os.environ, {"HOME": str(self.home), "AM_I_AFFECTED_BIN": str(self.agent)}
        )
        patch.start()
        self.addCleanup(patch.stop)

    def script(self, body):
        self.agent.write_text("#!/usr/bin/env python3\n" + body)
        self.agent.chmod(0o755)

    def run_main(self, command):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            result = affected.main([command])
        return result, output.getvalue()

    def test_absent_agent_is_silent_and_optional(self):
        for command in (
            "status",
            "codex-status",
            "after-apply",
            "collect-and-push",
            "watch-wake",
        ):
            self.assertEqual(self.run_main(command), (0, ""))

    def test_delegated_commands_replace_wrapper_and_preserve_arguments_path_exit_status(
        self,
    ):
        for command in ("collect-and-push", "watch-wake"):
            for exit_status in (0, 7):
                with self.subTest(command=command, exit_status=exit_status):
                    self.script(
                        "import json, os, pathlib, sys\n"
                        "result = {'pid': os.getpid(), 'args': sys.argv[1:], "
                        "'path': os.environ['PATH'], 'cwd': os.getcwd(), 'stdin': sys.stdin.read()}\n"
                        "(pathlib.Path.home() / 'exec-result.json').write_text(json.dumps(result))\n"
                        "print('agent output')\nprint('agent error', file=sys.stderr)\n"
                        f"sys.exit({exit_status})\n"
                    )
                    with subprocess.Popen(
                        [
                            sys.executable,
                            str(ROOT / "bin/executable_affected-agent"),
                            command,
                        ],
                        cwd=ROOT,
                        stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    ) as process:
                        output, errors = process.communicate(
                            input=b"caller input", timeout=5
                        )
                    result = json.loads((self.home / "exec-result.json").read_text())
                    self.assertEqual(process.returncode, exit_status)
                    collecting = command == "collect-and-push"
                    self.assertEqual(output, b"" if collecting else b"agent output\n")
                    self.assertEqual(errors, b"" if collecting else b"agent error\n")
                    self.assertEqual(
                        result["cwd"],
                        str((self.home if collecting else ROOT).resolve()),
                    )
                    self.assertEqual(
                        result["stdin"], "" if collecting else "caller input"
                    )
                    self.assertEqual(result["pid"], process.pid)
                    self.assertEqual(result["args"], [command])
                    self.assertEqual(
                        result["path"].split(os.pathsep)[:3],
                        [
                            str(self.home / ".nix-profile/bin"),
                            str(self.home / ".local/bin"),
                            "/run/current-system/sw/bin",
                        ],
                    )

    def test_delegation_failure_returns_one(self):
        self.agent.write_text("#!/missing-interpreter\n")
        self.agent.chmod(0o755)
        for command in ("collect-and-push", "watch-wake"):
            with self.subTest(command=command):
                result = subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "bin/executable_affected-agent"),
                        command,
                    ],
                    capture_output=True,
                    timeout=5,
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual((result.stdout, result.stderr), (b"", b""))

    def test_status_only_requests_cached_status_and_returns_ui_json(self):
        self.script(
            "import pathlib, sys\n"
            "pathlib.Path('called').write_text(sys.argv[1])\n"
            "print('AIA: open 2 / pending 1 / Mac 2026-10-25 / cloud 2026-10-24')\n"
        )
        code, output = self.run_main("codex-status")
        self.assertEqual(code, 0)
        self.assertEqual((self.home / "called").read_text(), "status")
        self.assertEqual(
            json.loads(output),
            {
                "systemMessage": "AIA: open 2 / pending 1 / Mac 2026-10-25 / cloud 2026-10-24"
            },
        )

    def test_failures_do_not_break_apply_or_claim_known_status(self):
        self.script(
            "import sys\nprint('sensitive failure', file=sys.stderr)\nsys.exit(7)\n"
        )
        self.assertEqual(self.run_main("after-apply"), (0, ""))
        self.assertEqual(self.run_main("status"), (0, affected.UNAVAILABLE + "\n"))

    def test_status_and_after_apply_deadlines_keep_sessions_and_apply_usable(self):
        self.script("import time\ntime.sleep(30)\n")
        for command, deadline, expected in (
            ("status", 0.5, affected.UNAVAILABLE + "\n"),
            ("after-apply", 2, ""),
        ):
            with self.subTest(command=command):
                started = time.monotonic()
                self.assertEqual(self.run_main(command), (0, expected))
                self.assertLess(time.monotonic() - started, deadline + 1)


@unittest.skipUnless(shutil.which("chezmoi"), "chezmoi is not installed")
class ChezmoiIntegrationTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.source = self.root / "source"
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        for name in (
            ".chezmoiignore",
            "bin/executable_affected-agent",
            "run_after_zz-notify-affected.sh.tmpl",
            "Library/LaunchAgents/local.am-i-affected.plist.tmpl",
            "Library/LaunchAgents/local.am-i-affected-wake.plist.tmpl",
            "dot_codex/hooks.json.tmpl",
            "dot_claude/settings.json.tmpl",
            ".chezmoitemplates/pr-format-judge.txt",
            "dot_claude/skills/vulnerability-remediation/SKILL.md",
        ):
            destination = self.source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)
        self.agent = self.root / "agent"
        self.agent.write_text('#!/bin/sh\nprintf \'%s\\n\' "$1" >> "$HOME/invoked"\n')
        self.agent.chmod(0o755)

    def apply(self, machine):
        return subprocess.run(
            [
                "chezmoi",
                "--config",
                str(ROOT / f"tests/chezmoi/{machine}.toml"),
                "--source",
                str(self.source),
                "--destination",
                str(self.home),
                "--persistent-state",
                str(self.root / "state.boltdb"),
                "apply",
                "--force",
            ],
            env={
                **os.environ,
                "HOME": str(self.home),
                "AM_I_AFFECTED_BIN": str(self.agent),
            },
            capture_output=True,
            text=True,
            timeout=60,
        )

    def test_personal_application_generates_calendar_and_invokes_after_success(self):
        result = self.apply("personal")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / "invoked").read_text(), "after-apply\n")
        plist = plistlib.loads(
            (self.home / "Library/LaunchAgents/local.am-i-affected.plist").read_bytes()
        )
        self.assertEqual(
            plist["StartCalendarInterval"],
            [{"Hour": hour, "Minute": 0} for hour in range(0, 24, 3)],
        )
        self.assertNotIn("RunAtLoad", plist)
        wake = plistlib.loads(
            (
                self.home / "Library/LaunchAgents/local.am-i-affected-wake.plist"
            ).read_bytes()
        )
        self.assertEqual(wake["ProgramArguments"][-1], "watch-wake")
        self.assertEqual(wake["KeepAlive"], {"SuccessfulExit": False})
        self.assertEqual(wake["ThrottleInterval"], 60)
        hooks = json.loads((self.home / ".codex/hooks.json").read_text())
        self.assertIn(
            "affected-agent codex-status",
            hooks["hooks"]["SessionStart"][0]["hooks"][1]["command"],
        )
        command = json.loads((self.home / ".claude/settings.json").read_text())[
            "statusLine"
        ]["command"]
        statusline = self.home / ".claude/statusline-command.sh"
        statusline.write_text("#!/bin/sh\ncat\n")
        statusline.chmod(0o755)
        self.agent.write_text(
            "#!/bin/sh\nprintf 'AIA: open 2 / pending 1 / Mac unknown / cloud unknown\\n'\n"
        )
        output = subprocess.check_output(
            ["/bin/sh", "-c", command],
            input="session-input\n",
            text=True,
            env={
                **os.environ,
                "HOME": str(self.home),
                "AM_I_AFFECTED_BIN": str(self.agent),
            },
        )
        self.assertEqual(
            output.splitlines(),
            ["AIA: open 2 / pending 1 / Mac unknown / cloud unknown", "session-input"],
        )

    def test_work_application_contains_no_collector_sender_or_startup_invocation(self):
        result = self.apply("work")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / "bin/affected-agent").exists())
        self.assertFalse(
            (self.home / "Library/LaunchAgents/local.am-i-affected.plist").exists()
        )
        self.assertFalse(
            (self.home / "Library/LaunchAgents/local.am-i-affected-wake.plist").exists()
        )
        self.assertFalse((self.home / "invoked").exists())
        hooks = (self.home / ".codex/hooks.json").read_text()
        self.assertNotIn("affected-agent", hooks)
        command = json.loads((self.home / ".claude/settings.json").read_text())[
            "statusLine"
        ]["command"]
        self.assertNotIn("affected-agent", command)
        self.assertTrue(
            (self.home / ".claude/skills/vulnerability-remediation/SKILL.md").is_file()
        )

    def test_failed_application_does_not_request_collection(self):
        (self.source / "run_after_a-fail.sh").write_text("#!/bin/sh\nexit 1\n")
        result = self.apply("personal")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "invoked").exists())

    def test_agent_failure_cannot_fail_application(self):
        self.agent.write_text("#!/bin/sh\nexit 1\n")
        result = self.apply("personal")
        self.assertEqual(result.returncode, 0, result.stderr)


class ProfileIntegrationTest(unittest.TestCase):
    def test_only_successful_profile_updates_notify(self):
        with tempfile.TemporaryDirectory() as directory:
            for result in (0, 1):
                with (
                    mock.patch.object(
                        cli, "NIX_DOTFILES_PROFILE", Path(directory) / "profile"
                    ),
                    mock.patch.object(cli.shutil, "which", return_value="nix"),
                    mock.patch.object(cli, "resolve_repo_root", return_value=ROOT),
                    mock.patch.object(
                        cli, "run_capture", return_value='{"elements":{}}'
                    ),
                    mock.patch.object(
                        cli,
                        "run_command",
                        return_value=subprocess.CompletedProcess([], result, "", ""),
                    ),
                    mock.patch.object(cli, "notify_affected_after_apply") as notify,
                    contextlib.redirect_stdout(io.StringIO()),
                    contextlib.redirect_stderr(io.StringIO()),
                ):
                    self.assertEqual(cli.command_sync_nix_profile(None), result)
                    self.assertEqual(notify.call_count, 1 if result == 0 else 0)
