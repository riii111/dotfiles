import contextlib
import importlib.machinery
import importlib.util
import io
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
        self.assertEqual(self.run_main("after-apply"), (0, ""))

    def test_only_after_apply_is_forwarded(self):
        self.script('printf "%s" "$1" > "$HOME/called"\n')
        for command in ("status", "codex-status"):
            self.assertEqual(self.run_main(command), (2, ""))
        self.assertFalse((self.home / "called").exists())
        self.assertEqual(self.run_main("after-apply"), (0, ""))
        self.assertEqual((self.home / "called").read_text(), "after-apply")

    def test_failures_and_hangs_do_not_break_apply(self):
        for body in ("echo 'sensitive failure' >&2\nexit 7\n", "exec /bin/sleep 30\n"):
            with self.subTest(body=body):
                self.script(body)
                started = time.monotonic()
                self.assertEqual(self.run_main("after-apply"), (0, ""))
                self.assertLess(time.monotonic() - started, 3)


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
                rendered = self.chezmoi(
                    machine,
                    "execute-template",
                    "--file",
                    str(ROOT / "run_after_zz-notify-affected.sh.tmpl"),
                )
                self.assertEqual("affected-agent" in rendered, personal)

    def test_no_session_shows_the_monitor_status(self):
        for template in ("dot_codex/hooks.json.tmpl", "dot_claude/settings.json.tmpl"):
            with self.subTest(template=template):
                rendered = self.chezmoi(
                    "personal", "execute-template", "--file", str(ROOT / template)
                )
                self.assertNotIn("affected", rendered)
