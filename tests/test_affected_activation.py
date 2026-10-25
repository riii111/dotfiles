import json
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
                "user = host.config.system.primaryUser; "
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
