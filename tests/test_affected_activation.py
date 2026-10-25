import json
import os
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

    def test_generated_callback_uses_user_context_and_preserves_activation_result(self):
        user = self.hosts["personal"]["user"]
        script = self.hosts["personal"]["script"]
        callback = script[script.index("\nif [[ -x /Users/") :]
        with tempfile.TemporaryDirectory() as directory:
            scratch = Path(directory)
            agent = scratch / "agent with spaces"
            calls = scratch / "calls.json"
            launcher = scratch / "launchctl"
            launcher.write_text(
                "#!/usr/bin/env python3\nimport json, os, sys\n"
                "with open(os.environ['CALL_LOG'], 'w') as output:\n"
                "    json.dump(sys.argv[1:], output)\n"
                "os.execv(sys.argv[-2], sys.argv[-2:])\n"
            )
            launcher.chmod(0o755)
            identity = scratch / "id"
            identity.write_text("#!/bin/sh\nprintf '1234\\n'\n")
            identity.chmod(0o755)
            callback = callback.replace(
                f"/Users/{user}/bin/affected-agent", shlex.quote(str(agent))
            )
            callback = callback.replace("/bin/launchctl", shlex.quote(str(launcher)))
            callback = callback.replace("/usr/bin/id", shlex.quote(str(identity)))
            for preceding_status, agent_status, installed in (
                (0, 0, True),
                (0, 7, True),
                (7, 0, True),
                (0, 0, False),
            ):
                with self.subTest(
                    preceding_status=preceding_status,
                    agent_status=agent_status,
                    installed=installed,
                ):
                    calls.unlink(missing_ok=True)
                    agent.write_text(
                        f'#!/bin/sh\n[ "$1" = after-apply ] || exit 99\nexit {agent_status}\n'
                    )
                    agent.chmod(0o755 if installed else 0o644)
                    result = subprocess.run(
                        [
                            "bash",
                            "-c",
                            f"set -e\n(exit {preceding_status})\n" + callback,
                        ],
                        env={**os.environ, "CALL_LOG": str(calls)},
                        timeout=5,
                    )
                    self.assertEqual(result.returncode, preceding_status)
                    self.assertEqual(
                        calls.exists(), preceding_status == 0 and installed
                    )
                    if calls.exists():
                        arguments = json.loads(calls.read_text())
                        self.assertEqual(
                            arguments[:3], ["asuser", "1234", "/usr/bin/sudo"]
                        )
                        self.assertIn("--non-interactive", arguments)
                        self.assertIn("--set-home", arguments)
                        self.assertIn(f"--user={user}", arguments)
                        self.assertEqual(arguments[-2:], [str(agent), "after-apply"])
