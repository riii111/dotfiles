import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SELECTOR_PATH = Path(__file__).with_name("selection.py")
spec = importlib.util.spec_from_file_location("ci_selector", SELECTOR_PATH)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)

ACTIVATION = "tests/ondemand/test_affected_activation.py"
INTEGRATION = "tests/ondemand/test_affected_integration.py"


class SelectionTests(unittest.TestCase):
    def test_path_categories_and_ondemand_targets(self):
        cases = [
            (["README.md"], set()),
            # No on-demand test reads Markdown, even under a directory it exercises.
            (["darwin/README.md"], set()),
            (["dot_codex/skills/example/SKILL.md"], {"cloud"}),
            # Unclassified paths select what --full does, on-demand tests included.
            (["nix/moonbit.nix"], selector.full()),
            (["new-unclassified-file"], selector.full()),
            (["dot-tools/permission/policy.mbt"], {"dot_tools", "repo", "hooks"}),
            # The CLI profile and the Darwin configurations consume the package recipe.
            (["dot-tools/package.nix"], selector.full()),
            (["scripts/build-open-apps.sh"], {"repo"}),
            # Narrow categories must still pull in the integration tests they affect.
            (["darwin/hosts/personal.nix"], {"nix", "repo", "hooks", ACTIVATION}),
            (["bin/lib/dot/cli.py"], {"repo", INTEGRATION}),
            (["flake.lock"], selector.full()),
            # An on-demand test change runs that test and the repo checks that lint it.
            ([INTEGRATION], {INTEGRATION, "repo"}),
            (["tests/ondemand/test_new.py"], {"tests/ondemand/test_new.py", "repo"}),
            (["tests/ondemand/fixture.json"], selector.full()),
            # A helper is no test, and the tests importing it are unknown.
            (["tests/ondemand/helpers.py"], selector.all_ondemand() | {"repo"}),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                self.assertEqual(selector.select(paths), expected)

    def test_every_ondemand_target_changes_the_selection(self):
        # A target that would select its test anyway is dead weight, so each must matter.
        for name, targets in selector.ONDEMAND.items():
            for target in targets:
                path = target + "x" if target.endswith("/") else target
                with self.subTest(name=name, target=target):
                    test = selector.ONDEMAND_DIR + name
                    self.assertIn(test, selector.select([path]))
                    original = selector.ONDEMAND
                    selector.ONDEMAND = {**original, name: ()}
                    try:
                        self.assertNotIn(test, selector.select([path]))
                    finally:
                        selector.ONDEMAND = original

    def test_darwin_only_ondemand_tests_are_listed_separately(self):
        selected = {ACTIVATION, INTEGRATION, "tests/ondemand/test_new.py"}
        self.assertEqual(
            selector.ondemand_lists(selected),
            (
                [INTEGRATION, "tests/ondemand/test_new.py"],
                [ACTIVATION],
            ),
        )

    def test_diff_against_base_and_push_before(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", *args], cwd=repo, check=True, capture_output=True, text=True
                ).stdout.strip()

            def run(*args):
                return subprocess.run(
                    [sys.executable, str(SELECTOR_PATH), *args],
                    cwd=repo,
                    capture_output=True,
                    text=True,
                )

            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            (repo / "unknown").write_text("contents\n")
            git("add", ".")
            git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD")
            # The old side of a rename still selects its checks.
            git("mv", "unknown", "renamed.md")
            git("commit", "-qm", "rename")
            self.assertIn("repo=true", run("--base", base).stdout.splitlines())
            self.assertNotEqual(run("--base", "bad-base").returncode, 0)

            before = git("rev-parse", "HEAD")
            (repo / "renamed.md").write_text("docs\n")
            git("commit", "-qam", "docs only")
            self.assertIn("repo=false", run("--before", before).stdout.splitlines())
            # A new branch or a force push has no usable before, so check everything.
            for before in ("", "0" * 40, "1" * 40):
                with self.subTest(before=before):
                    lines = run("--before", before).stdout.splitlines()
                    self.assertIn("repo=true", lines)
                    # Only on-demand tests present in the checkout are listed.
                    self.assertIn("ondemand=", lines)
                    self.assertIn("ondemand_darwin=", lines)


if __name__ == "__main__":
    unittest.main()
