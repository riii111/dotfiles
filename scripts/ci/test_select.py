import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli

SELECTOR_PATH = Path(__file__).with_name("selection.py")
spec = importlib.util.spec_from_file_location("ci_selector", SELECTOR_PATH)
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


class SelectionTests(unittest.TestCase):
    def test_path_categories_and_combinations(self):
        cases = [
            (["README.md"], set()),
            (["dot_codex/skills/example/SKILL.md"], {"cloud"}),
            ([".chezmoitemplates/agents-common.md"], {"cloud"}),
            (["flake.nix"], selector.ALL),
            (["nix/moonbit.nix"], selector.ALL),
            (["dot-tools/permission/policy.mbt"], {"dot_tools", "repo", "hooks"}),
            (["bin/lib/dot/cli.py"], {"repo"}),
            (["scripts/build-open-apps.sh"], {"repo"}),
            (["tests/test_macos_sdk_repair.py"], {"repo"}),
            (["darwin/common.nix"], {"nix", "repo", "hooks"}),
            ([".github/workflows/main-verify.yml"], selector.ALL),
            (["new-unclassified-file"], selector.ALL),
            (
                ["README.md", "dot-tools/permission/policy.mbt"],
                {"dot_tools", "repo", "hooks"},
            ),
        ]
        for paths, expected in cases:
            with self.subTest(paths=paths):
                self.assertEqual(selector.select(paths), expected)

    def test_diff_includes_old_path_of_rename_and_fails_on_bad_base(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)

            def git(*args):
                return subprocess.run(
                    ["git", *args], cwd=repo, check=True, capture_output=True
                )

            git("init", "-q")
            git("config", "user.name", "Test")
            git("config", "user.email", "test@example.com")
            (repo / "unknown").write_text("contents\n")
            git("add", ".")
            git("commit", "-qm", "base")
            base = git("rev-parse", "HEAD").stdout.decode().strip()
            git("mv", "unknown", "renamed.md")
            git("commit", "-qm", "rename")
            result = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--base", base],
                cwd=repo,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(
                set(result.stdout.splitlines()),
                {f"{name}=true" for name in selector.ALL} | {"cloud=false"},
            )
            result = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--base", "bad-base"],
                cwd=repo,
                capture_output=True,
            )
            self.assertNotEqual(result.returncode, 0)

            template = repo / ".chezmoitemplates/agents-common.md"
            template.parent.mkdir()
            template.write_text("template\n")
            git("add", ".")
            git("commit", "-qm", "add template")
            base = git("rev-parse", "HEAD").stdout.decode().strip()
            git("rm", str(template.relative_to(repo)))
            git("commit", "-qm", "remove template")
            result = subprocess.run(
                [sys.executable, str(SELECTOR_PATH), "--base", base],
                cwd=repo,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("cloud=true", result.stdout.splitlines())
            self.assertIn("repo=false", result.stdout.splitlines())


class RepoCommandTests(unittest.TestCase):
    def test_hook_failures_propagate_and_skip_only_when_requested(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tests = root / "tests"
            tests.mkdir()
            for name in (
                "test-codex-permission-hook.sh",
                "test-comment-review-hook.sh",
                "test-other.sh",
            ):
                (tests / name).touch()
            calls = []

            def run(args, cwd):
                calls.append(args)
                code = int(args[-1].endswith("test-codex-permission-hook.sh"))
                return subprocess.CompletedProcess(args, code, "", "failed")

            with (
                mock.patch.object(cli, "resolve_repo_root", return_value=root),
                mock.patch.object(cli.shutil, "which", side_effect=lambda name: name),
                mock.patch.object(cli, "run_command", side_effect=run),
                mock.patch.object(cli, "collect_shell_targets", return_value=[]),
                mock.patch("builtins.print"),
            ):
                args = cli.build_parser().parse_args(["test"])
                self.assertEqual(cli.command_test(args), 1)
                self.assertTrue(
                    any(a[-1].endswith("test-comment-review-hook.sh") for a in calls)
                )
                calls.clear()
                args = cli.build_parser().parse_args(["test", "--skip-agent-hooks"])
                self.assertEqual(cli.command_test(args), 0)
                self.assertTrue(any(a[-1].endswith("test-other.sh") for a in calls))
                self.assertFalse(any("-hook.sh" in a[-1] for a in calls))


if __name__ == "__main__":
    unittest.main()
