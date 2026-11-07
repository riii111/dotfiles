import json
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
# It evaluates the Darwin configurations, which only a macOS runner can import.
# dotctl and scripts/ci/selection.py read this line to run it on macOS only.
REQUIRES_DARWIN = True


@unittest.skipUnless(shutil.which("nix"), "nix is not installed")
class DarwinActivationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            [
                "nix",
                "eval",
                "--offline",
                "--json",
                ".#darwinConfigurations",
                "--apply",
                "hosts: builtins.mapAttrs (_: host: { "
                "agents = builtins.mapAttrs (_: agent: agent.text) host.config.environment.userLaunchAgents; "
                "commands = builtins.mapAttrs (_: agent: agent.script) host.config.launchd.user.agents; "
                "script = host.config.system.activationScripts.script.text; }) hosts",
            ],
            cwd=ROOT,
            text=True,
            capture_output=True,
            timeout=60,
        )
        if result.returncode:
            # Offline evaluation fails when the flake inputs are not cached.
            raise unittest.SkipTest(f"nix eval failed: {result.stderr[-500:]}")
        cls.hosts = json.loads(result.stdout)

    def test_work_machine_has_no_monitoring(self):
        work = self.hosts["work"]
        self.assertNotIn("local.am-i-affected.plist", work["agents"])
        self.assertNotIn("affected-agent", work["script"])

    def test_direct_collection_is_optional_and_does_not_expose_agent_output(self):
        personal = self.hosts["personal"]
        calendar = plistlib.loads(
            personal["agents"]["local.am-i-affected.plist"].encode()
        )
        installed = calendar["WorkingDirectory"] + "/.local/bin/am-i-affected"
        self.assertIn(
            "/opt/homebrew/bin", calendar["EnvironmentVariables"]["PATH"].split(":")
        )
        with tempfile.TemporaryDirectory() as directory:
            agent = Path(directory) / "agent with spaces"
            calls = Path(directory) / "calls"
            commands = {
                name: script.replace(installed, shlex.quote(str(agent)))
                for name, script in personal["commands"].items()
            }
            for script in commands.values():
                result = subprocess.run(
                    ["/bin/sh", "-c", script], capture_output=True, timeout=30
                )
                self.assertEqual(
                    (result.returncode, result.stdout, result.stderr), (0, b"", b"")
                )
            agent.write_text(
                f'#!/bin/sh\nprintf "%s\\n" "$1" > {shlex.quote(str(calls))}\n'
                "echo private-output\necho private-error >&2\nexit 7\n"
            )
            agent.chmod(0o755)
            result = subprocess.run(
                ["/bin/sh", "-c", commands["affected"]], capture_output=True, timeout=30
            )
            self.assertEqual(result.returncode, 7)
            self.assertEqual(calls.read_text(), "collect-and-push\n")
            self.assertEqual((result.stdout, result.stderr), (b"", b""))
