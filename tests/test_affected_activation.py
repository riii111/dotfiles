import json
import plistlib
import shlex
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


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
            raise RuntimeError(result.stderr)
        cls.hosts = json.loads(result.stdout)

    def test_only_personal_notifies_after_all_system_pointer_updates(self):
        script = self.hosts["personal"]["script"]
        self.assertIn("\nset -e\n", script)
        hook = script.index("\nif [[ -x /Users/")
        self.assertGreater(
            hook,
            script.index(
                'ln -sfn "$(readlink -f "$systemConfig")" /run/current-system'
            ),
        )
        self.assertGreater(
            hook,
            script.index(
                "ln -sfn /run/current-system /nix/var/nix/gcroots/current-system"
            ),
        )
        self.assertNotIn("affected-agent", self.hosts["work"]["script"])

    def test_only_personal_manages_calendar_agent(self):
        personal = self.hosts["personal"]["agents"]
        calendar = plistlib.loads(personal["local.am-i-affected.plist"].encode())
        self.assertEqual(calendar["Label"], "local.am-i-affected")
        self.assertEqual(
            calendar["StartCalendarInterval"],
            [{"Hour": hour, "Minute": 0} for hour in range(0, 24, 3)],
        )
        self.assertNotIn("local.am-i-affected-wake.plist", personal)
        self.assertNotIn("local.am-i-affected.plist", self.hosts["work"]["agents"])
        self.assertNotIn("local.am-i-affected-wake.plist", self.hosts["work"]["agents"])

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
