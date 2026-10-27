import contextlib
import importlib.machinery
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


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
        self.agent = self.home / ".local/bin/am-i-affected"
        self.agent.parent.mkdir(parents=True)
        patch = mock.patch.dict(os.environ, {"HOME": str(self.home)})
        patch.start()
        self.addCleanup(patch.stop)

    def script(self, body):
        self.agent.write_text("#!/bin/sh\n" + body)
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
        ):
            self.assertEqual(self.run_main(command), (0, ""))

    def test_status_only_requests_cached_status_and_returns_ui_json(self):
        self.script(
            "echo 'AIA: previous cache'\n"
            'printf "%s" "$1" > "$HOME/called"\n'
            'printf "%s" "$AM_I_AFFECTED_STATUS_DEADLINE" > "$HOME/deadline"\n'
            "echo 'AIA: open 2 / pending 1 / Mac 2026-10-25 / cloud 2026-10-24'\n"
        )
        started = time.monotonic()
        code, output = self.run_main("codex-status")
        self.assertEqual(code, 0)
        self.assertEqual((self.home / "called").read_text(), "status")
        deadline = float((self.home / "deadline").read_text())
        self.assertGreater(deadline, started)
        self.assertLess(deadline, started + 0.5)
        self.assertEqual(
            json.loads(output),
            {
                "systemMessage": "AIA: open 2 / pending 1 / Mac 2026-10-25 / cloud 2026-10-24"
            },
        )

    def test_timeout_retains_flushed_cache_in_codex_message(self):
        self.script("printf 'cached status\\n\\n'\nexec /bin/sleep 30\n")
        started = time.monotonic()
        code, output = self.run_main("codex-status")
        self.assertLess(time.monotonic() - started, 1)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output), {"systemMessage": "cached status"})

    def test_failures_do_not_break_apply_or_claim_known_status(self):
        self.script("echo 'sensitive failure' >&2\nexit 7\n")
        self.assertEqual(self.run_main("after-apply"), (0, ""))
        self.assertEqual(self.run_main("status"), (0, affected.UNAVAILABLE + "\n"))

    def test_status_and_after_apply_deadlines_keep_sessions_and_apply_usable(self):
        self.script("exec /bin/sleep 30\n")
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
        self.home = self.root / "home with spaces"
        self.home.mkdir()

    def chezmoi(self, machine, *args):
        return subprocess.check_output(
            [
                "chezmoi",
                "--config",
                str(ROOT / f"tests/chezmoi/{machine}.toml"),
                "--source",
                str(ROOT),
                "--destination",
                str(self.home),
                "--persistent-state",
                str(self.root / "state.boltdb"),
                *args,
            ],
            env={**os.environ, "HOME": str(self.home)},
            text=True,
            timeout=60,
        )

    def test_only_personal_generates_monitoring_invocations(self):
        for machine in ("personal", "work"):
            with self.subTest(machine=machine):
                personal = machine == "personal"
                paths = self.chezmoi(
                    machine, "managed", "--include=files", "--path-style=relative"
                ).splitlines()
                self.assertEqual("bin/affected-agent" in paths, personal)
                self.assertFalse(any(path.startswith("Library/") for path in paths))
                for template in (
                    "dot_codex/hooks.json.tmpl",
                    "dot_claude/settings.json.tmpl",
                    "run_after_zz-notify-affected.sh.tmpl",
                ):
                    rendered = self.chezmoi(
                        machine, "execute-template", "--file", str(ROOT / template)
                    )
                    self.assertEqual("affected-agent" in rendered, personal)

    def test_personal_status_preserves_session_input_with_spaces_in_home(self):
        command = json.loads(
            self.chezmoi(
                "personal",
                "execute-template",
                "--file",
                str(ROOT / "dot_claude/settings.json.tmpl"),
            )
        )["statusLine"]["command"]
        wrapper = self.home / "bin/affected-agent"
        wrapper.parent.mkdir()
        shutil.copyfile(ROOT / "bin/executable_affected-agent", wrapper)
        statusline = self.home / ".claude/statusline-command.sh"
        statusline.parent.mkdir()
        statusline.write_text("#!/bin/sh\ncat\n")
        statusline.chmod(0o755)
        agent = self.home / ".local/bin/am-i-affected"
        agent.parent.mkdir(parents=True)
        agent.write_text(
            "#!/bin/sh\nprintf 'AIA: open 2 / pending 1 / Mac unknown / cloud unknown\\n'\n"
        )
        agent.chmod(0o755)
        output = subprocess.check_output(
            ["/bin/sh", "-c", command],
            input="session-input\n",
            text=True,
            env={**os.environ, "HOME": str(self.home)},
        )
        self.assertEqual(
            output.splitlines(),
            ["AIA: open 2 / pending 1 / Mac unknown / cloud unknown", "session-input"],
        )
