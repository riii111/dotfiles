import io
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli


class DotCliTest(unittest.TestCase):
    def test_detect_shell_uses_shebang_and_skips_python(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bash_script = root / "script"
            bash_script.write_text("#!/usr/bin/env bash\necho hi\n", encoding="utf-8")

            python_script = root / "tool"
            python_script.write_text(
                "#!/usr/bin/env python3\nprint('hi')\n", encoding="utf-8"
            )

            self.assertEqual(cli.detect_shell(bash_script), "bash")
            self.assertIsNone(cli.detect_shell(python_script))

    def test_detect_shell_skips_exotic_shebangs(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            fish_script = root / "script"
            fish_script.write_text("#!/usr/bin/env fish\necho hi\n", encoding="utf-8")

            self.assertIsNone(cli.detect_shell(fish_script))

    def test_detect_shebang_shell_handles_env_dash_s(self):
        self.assertEqual(
            cli.detect_shebang_shell("#!/usr/bin/env -S bash -eu"),
            "bash",
        )

    def test_detect_shebang_shell_returns_none_when_env_only_has_flags(self):
        self.assertIsNone(cli.detect_shebang_shell("#!/usr/bin/env -Sbash"))

    def test_collect_shell_targets_skips_templates(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bash_script = root / "scripts" / "check.sh"
            bash_script.parent.mkdir()
            bash_script.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")

            zsh_template = root / "dot_zshrc.tmpl"
            zsh_template.write_text('{{ if eq .type "work" }}\n', encoding="utf-8")

            with mock.patch.object(
                cli, "git_tracked_files", return_value=[bash_script, zsh_template]
            ):
                targets = cli.collect_shell_targets(root)

        self.assertEqual(targets, [(bash_script, "bash")])

    def test_check_env_returns_error_when_required_missing(self):
        fake_paths = {
            "git": "/usr/bin/git",
            "python3": "/usr/bin/python3",
        }

        def fake_which(name):
            return fake_paths.get(name)

        with (
            mock.patch("shutil.which", side_effect=fake_which),
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()),
        ):
            result = cli.command_check_env(mock.Mock())

        self.assertEqual(result, 1)

    def test_check_env_reports_nvim_failure_and_continues(self):
        def fake_which(name):
            return {
                "git": "/usr/bin/git",
                "python3": "/usr/bin/python3",
                "chezmoi": "/opt/homebrew/bin/chezmoi",
                "brew": "/opt/homebrew/bin/brew",
                "nvim": "/opt/homebrew/bin/nvim",
                "lefthook": "/opt/homebrew/bin/lefthook",
                "nix": "/nix/var/nix/profiles/default/bin/nix",
            }.get(name)

        with (
            mock.patch("shutil.which", side_effect=fake_which),
            mock.patch(
                "subprocess.run",
                return_value=subprocess.CompletedProcess(
                    ["/opt/homebrew/bin/nvim", "--headless", "+qa"],
                    1,
                    "",
                    "init failed",
                ),
            ),
            mock.patch("sys.stdout", new=io.StringIO()) as stdout,
            mock.patch("sys.stderr", new=io.StringIO()) as stderr,
        ):
            result = cli.command_check_env(mock.Mock())

        self.assertEqual(result, 1)
        self.assertIn("nvim: OK", stdout.getvalue())
        self.assertIn("nvim headless: FAILED", stderr.getvalue())

    def test_collect_lintable_shell_targets_excludes_zsh_and_templates(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bash_script = root / "scripts" / "check.sh"
            bash_script.parent.mkdir()
            bash_script.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")

            zsh_script = root / "hooks" / "hook.zsh"
            zsh_script.parent.mkdir()
            zsh_script.write_text("#!/bin/zsh\nprint ok\n", encoding="utf-8")

            template = root / "dot_zshrc.tmpl"
            template.write_text("#!/bin/zsh\n{{ end }}\n", encoding="utf-8")

            targets = cli.collect_lintable_shell_targets(
                [bash_script, zsh_script, template]
            )

        self.assertEqual(targets, [bash_script])

    def test_resolve_candidate_paths_skips_outside_repo(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir).resolve()
            inside = repo_root / "scripts" / "check.sh"
            inside.parent.mkdir()
            inside.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")

            outside_dir = repo_root.parent / "dot-outside-test"
            outside_dir.mkdir(exist_ok=True)
            outside = outside_dir / "outside.sh"
            outside.write_text("#!/usr/bin/env bash\necho ng\n", encoding="utf-8")

            try:
                paths = cli.resolve_candidate_paths(
                    repo_root,
                    ["scripts/check.sh", str(outside)],
                )
            finally:
                outside.unlink(missing_ok=True)
                outside_dir.rmdir()

        self.assertEqual(paths, [inside.resolve()])

    def test_resolve_repo_root_falls_back_to_chezmoi(self):
        with (
            mock.patch.object(
                cli,
                "run_capture",
                side_effect=[
                    subprocess.CalledProcessError(1, ["git"]),
                    "/tmp/dotfiles",
                ],
            ),
            mock.patch("shutil.which", return_value="/opt/homebrew/bin/chezmoi"),
        ):
            root = cli.resolve_repo_root()

        self.assertEqual(root, Path("/tmp/dotfiles").resolve())

    def test_resolve_repo_root_raises_when_no_fallback_exists(self):
        with (
            mock.patch.object(
                cli,
                "run_capture",
                side_effect=subprocess.CalledProcessError(1, ["git"]),
            ),
            mock.patch("shutil.which", return_value=None),
        ):
            with self.assertRaises(RuntimeError):
                cli.resolve_repo_root()

    def test_command_test_runs_unittest_and_shell_checks(self):
        repo_root = Path("/repo")
        targets = [
            (repo_root / "scripts/check.sh", "bash"),
            (repo_root / "bin/run", "sh"),
        ]
        calls = []

        def fake_run(args, **kwargs):
            calls.append((tuple(args), kwargs))
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch.object(cli, "collect_shell_targets", return_value=targets),
            mock.patch(
                "shutil.which",
                side_effect=lambda name: f"/bin/{name}",
            ),
            mock.patch("subprocess.run", side_effect=fake_run),
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()),
        ):
            result = cli.command_test(mock.Mock())

        self.assertEqual(result, 0)
        self.assertEqual(
            calls[0][0], ("python3", "-m", "unittest", "discover", "tests")
        )
        self.assertEqual(calls[1][0], ("/bin/bash", "-n", "/repo/scripts/check.sh"))
        self.assertEqual(calls[2][0], ("/bin/sh", "-n", "/repo/bin/run"))

    def test_command_test_collects_failures_without_traceback(self):
        repo_root = Path("/repo")
        targets = [(repo_root / "scripts/check.sh", "bash")]
        runs = [
            subprocess.CompletedProcess(["python3"], 1, "", "unit failed"),
            subprocess.CompletedProcess(["bash"], 1, "", "syntax failed"),
        ]

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch.object(cli, "collect_shell_targets", return_value=targets),
            mock.patch("subprocess.run", side_effect=runs),
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()) as stderr,
        ):
            result = cli.command_test(mock.Mock())

        self.assertEqual(result, 1)
        self.assertIn("python tests: failed", stderr.getvalue())
        self.assertIn("Shell syntax failed", stderr.getvalue())

    def test_command_test_reports_missing_shell_binary(self):
        repo_root = Path("/repo")
        targets = [(repo_root / "scripts/check.zsh", "zsh")]

        def fake_which(name):
            if name == "zsh":
                return None
            return f"/bin/{name}"

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch.object(cli, "collect_shell_targets", return_value=targets),
            mock.patch("shutil.which", side_effect=fake_which),
            mock.patch(
                "subprocess.run",
                return_value=subprocess.CompletedProcess(
                    ["python3", "-m", "unittest", "discover", "tests"],
                    0,
                    "",
                    "",
                ),
            ),
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()) as stderr,
        ):
            result = cli.command_test(mock.Mock())

        self.assertEqual(result, 1)
        self.assertIn("zsh not found", stderr.getvalue())

    def test_command_lint_shell_runs_available_tools(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir).resolve()
            target = repo_root / "scripts" / "check.sh"
            target.parent.mkdir()
            target.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")
            calls = []

            def fake_run(args, **kwargs):
                calls.append(tuple(args))
                return subprocess.CompletedProcess(args, 0, "", "")

            def fake_which(name):
                return {
                    "shfmt": "/opt/homebrew/bin/shfmt",
                    "shellcheck": "/opt/homebrew/bin/shellcheck",
                }.get(name)

            with (
                mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
                mock.patch("shutil.which", side_effect=fake_which),
                mock.patch("subprocess.run", side_effect=fake_run),
                mock.patch("sys.stdout", new=io.StringIO()),
                mock.patch("sys.stderr", new=io.StringIO()),
            ):
                result = cli.command_lint_shell(mock.Mock(paths=["scripts/check.sh"]))

        self.assertEqual(result, 0)
        self.assertEqual(
            calls,
            [
                ("/opt/homebrew/bin/shfmt", "-w", "scripts/check.sh"),
                ("/opt/homebrew/bin/shellcheck", "scripts/check.sh"),
            ],
        )

    def test_command_lint_shell_skips_when_tools_missing(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir).resolve()
            target = repo_root / "scripts" / "check.sh"
            target.parent.mkdir()
            target.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")

            with (
                mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
                mock.patch("shutil.which", return_value=None),
                mock.patch("subprocess.run") as run,
                mock.patch("sys.stdout", new=io.StringIO()),
                mock.patch("sys.stderr", new=io.StringIO()),
            ):
                result = cli.command_lint_shell(mock.Mock(paths=["scripts/check.sh"]))

        self.assertEqual(result, 0)
        run.assert_not_called()

    def test_command_lint_staged_shell_uses_git_staged_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo_root = Path(tmpdir).resolve()
            staged = repo_root / "scripts" / "check.sh"
            staged.parent.mkdir()
            staged.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")

            with (
                mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
                mock.patch.object(cli, "git_staged_files", return_value=[staged]),
                mock.patch.object(
                    cli, "run_lint_shell_targets", return_value=0
                ) as lint_shell,
            ):
                result = cli.command_lint_staged_shell(mock.Mock())

        self.assertEqual(result, 0)
        lint_shell.assert_called_once()
        self.assertEqual(lint_shell.call_args.args[0], repo_root)
        self.assertEqual(lint_shell.call_args.args[1], [staged])

    def test_command_sync_nix_profile_upgrades_existing_profile_package(self):
        repo_root = Path("/repo")
        profile_path = Path("/tmp/nix-profile")
        calls = []

        def fake_run_command(args, cwd):
            calls.append((args, cwd))
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch(
                "shutil.which", return_value="/nix/var/nix/profiles/default/bin/nix"
            ),
            mock.patch.object(cli, "NIX_DOTFILES_PROFILE", profile_path),
            mock.patch.object(
                cli,
                "run_capture",
                return_value='{"elements":{"cli":{"active":true}},"version":3}',
            ),
            mock.patch.object(cli, "run_command", side_effect=fake_run_command),
            mock.patch("sys.stdout", new=io.StringIO()),
        ):
            result = cli.command_sync_nix_profile(mock.Mock())

        self.assertEqual(result, 0)
        self.assertEqual(
            calls[0][0],
            [
                "/nix/var/nix/profiles/default/bin/nix",
                "profile",
                "upgrade",
                "--profile",
                str(profile_path),
                "cli",
            ],
        )
        self.assertEqual(len(calls), 1)

    def test_command_sync_nix_profile_installs_when_profile_is_empty(self):
        repo_root = Path("/repo")
        profile_path = Path("/tmp/nix-profile")
        calls = []

        def fake_run_command(args, cwd):
            calls.append((args, cwd))
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch(
                "shutil.which", return_value="/nix/var/nix/profiles/default/bin/nix"
            ),
            mock.patch.object(cli, "NIX_DOTFILES_PROFILE", profile_path),
            mock.patch.object(
                cli,
                "run_capture",
                return_value='{"elements":{},"version":3}',
            ),
            mock.patch.object(cli, "run_command", side_effect=fake_run_command),
            mock.patch("sys.stdout", new=io.StringIO()),
        ):
            result = cli.command_sync_nix_profile(mock.Mock())

        self.assertEqual(result, 0)
        self.assertEqual(len(calls), 1)
        self.assertEqual(
            calls[0][0],
            [
                "/nix/var/nix/profiles/default/bin/nix",
                "profile",
                "add",
                "--profile",
                str(profile_path),
                ".#cli",
            ],
        )

    def test_command_sync_nix_profile_requires_nix(self):
        with (
            mock.patch("shutil.which", return_value=None),
            mock.patch.object(cli, "resolve_repo_root", return_value=Path("/repo")),
        ):
            with self.assertRaises(RuntimeError):
                cli.command_sync_nix_profile(mock.Mock())

    def test_command_work_tools_install_uses_ghq_for_missing_repo(self):
        calls = []
        tool_path = Path("/tmp/prod-errors")

        def fake_run_command(args, cwd):
            calls.append((args, cwd))
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(
                cli,
                "WORK_TOOL_REPOS",
                {
                    "prod-errors": {
                        "repo": "git@example.com:prod-errors.git",
                        "path": tool_path,
                    }
                },
            ),
            mock.patch.object(Path, "exists", return_value=False),
            mock.patch.object(cli, "run_command", side_effect=fake_run_command),
            mock.patch("sys.stdout", new=io.StringIO()),
        ):
            result = cli.command_work_tools_install(SimpleNamespace(name=None))

        self.assertEqual(result, 0)
        self.assertEqual(
            calls,
            [(["ghq", "get", "git@example.com:prod-errors.git"], Path.home())],
        )

    def test_command_work_tools_apply_runs_chezmoi_source_apply(self):
        calls = []
        tool_path = Path("/tmp/prod-errors")

        def fake_run_command(args, cwd):
            calls.append((args, cwd))
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(
                cli,
                "WORK_TOOL_REPOS",
                {
                    "prod-errors": {
                        "repo": "git@example.com:prod-errors.git",
                        "path": tool_path,
                    }
                },
            ),
            mock.patch.object(Path, "exists", return_value=True),
            mock.patch.object(cli, "run_command", side_effect=fake_run_command),
        ):
            result = cli.command_work_tools_apply(SimpleNamespace(name="prod-errors"))

        self.assertEqual(result, 0)
        self.assertEqual(
            calls,
            [
                (
                    [
                        "chezmoi",
                        "-S",
                        str(tool_path),
                        "apply",
                        "--force",
                        "--no-tty",
                    ],
                    tool_path,
                )
            ],
        )

    def test_command_work_tools_update_pulls_then_applies(self):
        calls = []
        tool_path = Path("/tmp/prod-errors")

        def fake_run_command(args, cwd):
            calls.append((args, cwd))
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(
                cli,
                "WORK_TOOL_REPOS",
                {
                    "prod-errors": {
                        "repo": "git@example.com:prod-errors.git",
                        "path": tool_path,
                    }
                },
            ),
            mock.patch.object(Path, "exists", return_value=True),
            mock.patch.object(cli, "run_command", side_effect=fake_run_command),
        ):
            result = cli.command_work_tools_update(SimpleNamespace(name=None))

        self.assertEqual(result, 0)
        self.assertEqual(
            calls,
            [
                (["git", "pull", "--ff-only"], tool_path),
                (
                    [
                        "chezmoi",
                        "-S",
                        str(tool_path),
                        "apply",
                        "--force",
                        "--no-tty",
                    ],
                    tool_path,
                ),
            ],
        )

    def test_command_work_tools_apply_requires_installed_repo(self):
        with (
            mock.patch.object(
                cli,
                "WORK_TOOL_REPOS",
                {
                    "prod-errors": {
                        "repo": "git@example.com:prod-errors.git",
                        "path": Path("/tmp/prod-errors"),
                    }
                },
            ),
            mock.patch.object(Path, "exists", return_value=False),
        ):
            with self.assertRaises(RuntimeError):
                cli.command_work_tools_apply(SimpleNamespace(name="prod-errors"))

    def test_command_work_tools_rejects_unknown_name(self):
        with self.assertRaises(RuntimeError):
            cli.command_work_tools_apply(SimpleNamespace(name="unknown"))

    def test_read_first_line_returns_empty_on_oserror(self):
        path = Path("/tmp/unreadable")
        with mock.patch.object(Path, "open", side_effect=PermissionError):
            self.assertEqual(cli.read_first_line(path), "")


if __name__ == "__main__":
    unittest.main()
