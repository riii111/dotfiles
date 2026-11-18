import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "run_once_after_migrate-pr-review.py"


class PrReviewMigrationTest(unittest.TestCase):
    def run_migration(self, home):
        subprocess.run(
            ["python3", str(SCRIPT)],
            env={**os.environ, "HOME": str(home)},
            check=True,
            capture_output=True,
            text=True,
        )

    def test_preserves_choice_ids_and_custom_settings_on_repeated_runs(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            path = home / ".config/pr-wake/review.json"
            path.parent.mkdir(parents=True)
            config = {
                "repositories": {"acme/app": "~/src/app"},
                "choices": [
                    {"id": "code", "skill": "code-review", "prompt": "code prompt"},
                    {"id": "adr", "skill": "adr-review", "prompt": "ADR prompt"},
                    {"id": "custom", "skill": "custom-review", "label": "Custom"},
                ],
            }
            path.write_text(json.dumps(config))
            path.chmod(0o600)

            self.run_migration(home)
            self.run_migration(home)

            config["choices"][0]["skill"] = "pr-review"
            config["choices"][1]["skill"] = "pr-review"
            self.assertEqual(json.loads(path.read_text()), config)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_does_not_create_an_unconfigured_review_service(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)

            self.run_migration(home)

            self.assertFalse((home / ".config/pr-wake").exists())


if __name__ == "__main__":
    unittest.main()
