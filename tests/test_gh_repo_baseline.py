import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/executable_gh-repo-baseline"

FAKE_GH = """#!/bin/sh
printf '%s\\n' "$*" >> "$GH_LOG"
case "$*" in
  *--input*) cat >> "$GH_LOG"; echo >> "$GH_LOG" ;;
  "repo view"*) echo me/current ;;
  "api --paginate repos/me/existing/rulesets"*) echo 7 ;;
  *"repos/me/broken"*) echo "HTTP 403: forbidden" >&2; exit 1 ;;
esac
if [ "$1" = api ]; then printf 'GH_REPO=%s\\n' "$GH_REPO" >> "$GH_LOG"; fi
"""


class GhRepoBaselineTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.log = self.root / "gh.log"
        fake = self.root / "gh"
        fake.write_text(FAKE_GH)
        fake.chmod(0o755)

    def run_script(self, *args):
        return subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            env={
                "PATH": os.pathsep.join((str(self.root), "/usr/bin", "/bin")),
                "GH_LOG": str(self.log),
            },
            capture_output=True,
            text=True,
            check=False,
        )

    def calls(self):
        return [
            line
            for line in self.log.read_text().splitlines()
            if not line.startswith(("{", "GH_REPO="))
        ]

    def gh_repos(self):
        return {
            line
            for line in self.log.read_text().splitlines()
            if line.startswith("GH_REPO=")
        }

    def bodies(self):
        return [
            json.loads(line)
            for line in self.log.read_text().splitlines()
            if line.startswith("{")
        ]

    def test_creates_ruleset_for_new_repository(self):
        result = self.run_script("me/new")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.calls(),
            [
                "api -X PATCH repos/me/new --input -",
                "api -X PUT repos/me/new/vulnerability-alerts",
                "api -X PUT repos/me/new/automated-security-fixes",
                'api --paginate repos/me/new/rulesets --jq .[] | select(.name == "baseline") | .id',
                "api -X POST repos/me/new/rulesets --input -",
            ],
        )
        self.assertEqual(self.gh_repos(), {"GH_REPO=me/new"})
        settings, ruleset = self.bodies()
        self.assertEqual(settings["delete_branch_on_merge"], True)
        self.assertEqual(
            [rule["type"] for rule in ruleset["rules"]],
            ["deletion", "non_fast_forward"],
        )

    def test_updates_existing_baseline_only(self):
        result = self.run_script("me/existing")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.calls()[-1], "api -X PUT repos/me/existing/rulesets/7 --input -"
        )

    def test_defaults_to_current_repository(self):
        result = self.run_script()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("api -X PATCH repos/me/current --input -", self.calls())

    def test_reports_failed_api_call(self):
        result = self.run_script("me/broken")

        self.assertEqual(result.returncode, 1)
        self.assertIn("HTTP 403: forbidden", result.stderr)


if __name__ == "__main__":
    unittest.main()
