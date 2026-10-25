import json
import plistlib
import shutil
import subprocess
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

    def test_personal_manages_calendar_and_wake_agents_without_failure_restart_loop(
        self,
    ):
        personal = self.hosts["personal"]["agents"]
        calendar = plistlib.loads(personal["local.am-i-affected.plist"].encode())
        wake = plistlib.loads(personal["local.am-i-affected-wake.plist"].encode())
        self.assertEqual(calendar["Label"], "local.am-i-affected")
        self.assertEqual(
            calendar["StartCalendarInterval"],
            [{"Hour": hour, "Minute": 0} for hour in range(0, 24, 3)],
        )
        self.assertEqual(wake["Label"], "local.am-i-affected-wake")
        self.assertTrue(wake["RunAtLoad"])
        self.assertFalse(wake["KeepAlive"])
        self.assertNotIn("local.am-i-affected.plist", self.hosts["work"]["agents"])
        self.assertNotIn("local.am-i-affected-wake.plist", self.hosts["work"]["agents"])
