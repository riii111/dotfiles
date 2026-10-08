import io
import shutil
import subprocess
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli


ROOT = Path(__file__).resolve().parents[1]


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

            fish_script = root / "fish_tool"
            fish_script.write_text("#!/usr/bin/env fish\necho hi\n", encoding="utf-8")

            self.assertEqual(cli.detect_shell(bash_script), "bash")
            self.assertIsNone(cli.detect_shell(python_script))
            self.assertIsNone(cli.detect_shell(fish_script))

    def test_detect_shebang_shell_handles_env_dash_s(self):
        self.assertEqual(
            cli.detect_shebang_shell("#!/usr/bin/env -S bash -eu"),
            "bash",
        )
        self.assertIsNone(cli.detect_shebang_shell("#!/usr/bin/env"))
        self.assertIsNone(cli.detect_shebang_shell("#!/usr/bin/env -S"))

    def test_detect_shell_classifies_templates_by_the_file_they_render_to(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)

            def template(name, text="# comment\n"):
                path = root / name
                path.write_text(text, encoding="utf-8")
                return path

            self.assertEqual(cli.detect_shell(template("dot_zshrc.tmpl")), "zsh")
            self.assertEqual(
                cli.detect_shell(template("private_dot_zshenv.tmpl")), "zsh"
            )
            self.assertEqual(cli.detect_shell(template("hook.zsh.tmpl")), "zsh")
            self.assertEqual(cli.detect_shell(template("install.sh.tmpl")), "bash")
            self.assertEqual(
                cli.detect_shell(template("tool.tmpl", "#!/usr/bin/env zsh\n")), "zsh"
            )
            self.assertIsNone(cli.detect_shell(template("config.toml.tmpl")))
            self.assertIsNone(
                cli.detect_shell(template("tool.py.tmpl", "#!/usr/bin/env python3\n"))
            )

    def test_detect_shell_treats_zsh_startup_files_as_zsh(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            for name in ("dot_zshenv", "dot_zprofile"):
                startup_file = root / name
                startup_file.write_text("export A=1\n", encoding="utf-8")
                self.assertEqual(cli.detect_shell(startup_file), "zsh")

            plain = root / "dot_psqlrc"
            plain.write_text("\\set QUIET 1\n", encoding="utf-8")
            self.assertIsNone(cli.detect_shell(plain))

    def test_collect_shell_targets_includes_shell_templates_only(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            bash_script = root / "scripts" / "check.sh"
            bash_script.parent.mkdir()
            bash_script.write_text("#!/usr/bin/env bash\necho ok\n", encoding="utf-8")

            zsh_template = root / "dot_zshrc.tmpl"
            zsh_template.write_text('{{ if eq .type "work" }}\n', encoding="utf-8")

            config_template = root / "config.toml.tmpl"
            config_template.write_text('name = "{{ .name }}"\n', encoding="utf-8")

            with mock.patch.object(
                cli,
                "git_tracked_files",
                return_value=[bash_script, zsh_template, config_template],
            ):
                targets = cli.collect_shell_targets(root)

        self.assertCountEqual(targets, [(bash_script, "bash"), (zsh_template, "zsh")])

    def test_collect_shell_template_targets_finds_the_repo_zshrc_template(self):
        zshrc = ROOT / "dot_zshrc.tmpl"
        chezmoi_config = ROOT / ".chezmoi.toml.tmpl"

        targets = cli.collect_shell_template_targets([zshrc, chezmoi_config])

        self.assertEqual(targets, [(zshrc, "zsh")])

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

            # shfmt -w would rewrite the actions of a bash template.
            bash_template = root / "install.sh.tmpl"
            bash_template.write_text("#!/bin/bash\n{{ end }}\n", encoding="utf-8")

            targets = cli.collect_lintable_shell_targets(
                [bash_script, zsh_script, template, bash_template]
            )

        self.assertEqual(targets, [bash_script])

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
        shell_test = repo_root / "tests/test-example.sh"
        calls = []

        def fake_run(args, **kwargs):
            calls.append(tuple(args))
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch.object(cli, "collect_shell_targets", return_value=targets),
            mock.patch.object(Path, "glob", return_value=[shell_test]),
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
        expected = [
            ("/bin/ruff", "check", "."),
            ("python3", "-m", "unittest", "discover", "tests"),
            ("/bin/bash", "/repo/tests/test-example.sh"),
            ("/bin/lua", "private_dot_config/wezterm/tests/herdr_mode_test.lua"),
            ("/bin/bash", "-n", "/repo/scripts/check.sh"),
            ("/bin/sh", "-n", "/repo/bin/run"),
        ]
        self.assertCountEqual(calls, expected)

    def test_command_test_collects_failures_without_traceback(self):
        repo_root = Path("/repo")
        targets = [(repo_root / "scripts/check.sh", "bash")]

        def fake_run(args, **kwargs):
            if "unittest" in args:
                return subprocess.CompletedProcess(args, 1, "", "unit failed")
            if "-n" in args:
                return subprocess.CompletedProcess(args, 1, "", "syntax failed")
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch.object(cli, "collect_shell_targets", return_value=targets),
            mock.patch("shutil.which", side_effect=lambda name: f"/bin/{name}"),
            mock.patch("subprocess.run", side_effect=fake_run),
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

        def fake_run(args, **kwargs):
            return subprocess.CompletedProcess(args, 0, "", "")

        with (
            mock.patch.object(cli, "resolve_repo_root", return_value=repo_root),
            mock.patch.object(cli, "collect_shell_targets", return_value=targets),
            mock.patch("shutil.which", side_effect=fake_which),
            mock.patch("subprocess.run", side_effect=fake_run),
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()) as stderr,
        ):
            result = cli.command_test(mock.Mock())

        self.assertEqual(result, 1)
        self.assertIn("zsh not found", stderr.getvalue())

    def make_template_repo(self, root, machines=cli.MACHINE_TYPES):
        """Write the test data files and the zsh template that a render needs."""
        data_dir = root / cli.CHEZMOI_TEST_DATA_DIR
        data_dir.mkdir(parents=True)
        for machine in machines:
            (data_dir / f"{machine}.toml").write_text(
                f'[data]\ntype = "{machine}"\n', encoding="utf-8"
            )
        template = root / "dot_zshrc.tmpl"
        template.write_text('{{ if eq .type "work" }}\n', encoding="utf-8")
        return template

    def run_command_test_for_template(
        self, fake_run, which=None, machines=cli.MACHINE_TYPES
    ):
        """Run command_test over a repo whose only shell target is a zsh template.

        Each render runs in a scratch directory, found through the HOME that
        chezmoi is given. None of them may be left behind once command_test returns.
        """
        if which is None:

            def which(name):
                return f"/bin/{name}"

        scratch_dirs = []

        def recording_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                scratch_dirs.append(Path(kwargs["env"]["HOME"]))
            return fake_run(args, **kwargs)

        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            template = self.make_template_repo(root, machines)

            with (
                mock.patch.object(cli, "resolve_repo_root", return_value=root),
                mock.patch.object(
                    cli, "collect_shell_targets", return_value=[(template, "zsh")]
                ),
                mock.patch("shutil.which", side_effect=which),
                mock.patch("subprocess.run", side_effect=recording_run),
                mock.patch("sys.stdout", new=io.StringIO()),
                mock.patch("sys.stderr", new=io.StringIO()) as stderr,
            ):
                result = cli.command_test(mock.Mock())

        for scratch in scratch_dirs:
            self.assertFalse(scratch.exists(), f"{scratch} was left behind")
        return SimpleNamespace(
            result=result,
            root=root,
            stderr=stderr.getvalue(),
            scratch_dirs=scratch_dirs,
        )

    def test_command_test_renders_shell_templates_for_each_machine_type(self):
        renders = {}
        syntax_checks = {}

        def fake_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                machine = Path(args[args.index("--config") + 1]).stem
                renders[machine] = (tuple(args), kwargs)
                rendered = f"print {machine}\n".encode()
                return subprocess.CompletedProcess(args, 0, rendered, b"")
            if "-n" in args:
                script = Path(args[-1])
                syntax_checks[script.name] = (
                    tuple(args[:-1]),
                    script.parent,
                    script.read_bytes(),
                )
            return subprocess.CompletedProcess(args, 0, "", "")

        outcome = self.run_command_test_for_template(fake_run)

        root = outcome.root
        self.assertEqual(outcome.result, 0, outcome.stderr)
        self.assertEqual(set(renders), {"personal", "work"})
        for machine, (args, kwargs) in renders.items():
            scratch = Path(kwargs["env"]["HOME"])
            self.assertEqual(
                args,
                (
                    "/bin/chezmoi",
                    "--config",
                    str(root / "tests" / "chezmoi" / f"{machine}.toml"),
                    "--source",
                    str(root),
                    "--persistent-state",
                    str(scratch / "chezmoistate.boltdb"),
                    "execute-template",
                    "--file",
                    str(root / "dot_zshrc.tmpl"),
                ),
            )
            # chezmoi sees only PATH and a throwaway HOME outside the repo.
            self.assertEqual(set(kwargs["env"]), {"PATH", "HOME"})
            self.assertNotIn(root, scratch.parents)
            # The rendered text, not the template, is what the shell checks.
            self.assertEqual(
                syntax_checks[f"dot_zshrc.{machine}"],
                (("/bin/zsh", "-n"), scratch, f"print {machine}\n".encode()),
            )
        self.assertEqual(len(syntax_checks), 2)
        self.assertEqual(len(outcome.scratch_dirs), len(cli.MACHINE_TYPES))

    def test_command_test_reports_template_render_failure(self):
        syntax_checks = []

        def fake_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                machine = Path(args[args.index("--config") + 1]).stem
                if machine == "work":
                    return subprocess.CompletedProcess(
                        args, 1, b"", b'map has no entry for key "gcp_projct"'
                    )
                return subprocess.CompletedProcess(args, 0, b"print ok\n", b"")
            if "-n" in args:
                syntax_checks.append(Path(args[-1]).name)
            return subprocess.CompletedProcess(args, 0, "", "")

        outcome = self.run_command_test_for_template(fake_run)

        stderr = outcome.stderr
        self.assertEqual(outcome.result, 1)
        self.assertIn("template render (dot_zshrc.tmpl for work): failed", stderr)
        self.assertIn('map has no entry for key "gcp_projct"', stderr)
        self.assertIn("Shell syntax failed: dot_zshrc.tmpl for work", stderr)
        self.assertNotIn("for personal", stderr)
        # A template that does not render is not syntax-checked.
        self.assertEqual(syntax_checks, ["dot_zshrc.personal"])
        # chezmoi's own message gives the line in the template, so no hint.
        self.assertNotIn("line numbers refer", stderr)
        self.assertEqual(len(outcome.scratch_dirs), len(cli.MACHINE_TYPES))

    def test_command_test_reports_template_syntax_failure(self):
        def fake_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                return subprocess.CompletedProcess(args, 0, b"print ok\n", b"")
            if "-n" in args and args[-1].endswith("dot_zshrc.work"):
                return subprocess.CompletedProcess(
                    args, 1, "", "dot_zshrc.work:3: parse error near `}'"
                )
            return subprocess.CompletedProcess(args, 0, "", "")

        outcome = self.run_command_test_for_template(fake_run)

        stderr = outcome.stderr
        self.assertEqual(outcome.result, 1)
        self.assertIn("shell syntax (dot_zshrc.tmpl for work): failed", stderr)
        self.assertIn("parse error near `}'", stderr)
        self.assertIn("Shell syntax failed: dot_zshrc.tmpl for work", stderr)
        self.assertNotIn("for personal", stderr)
        # The shell's line numbers are those of the render, so say how to get it.
        self.assertIn(
            "line numbers refer to the rendered text: chezmoi --config "
            "tests/chezmoi/work.toml --source . execute-template --file dot_zshrc.tmpl",
            stderr,
        )
        self.assertEqual(stderr.count("line numbers refer"), 1)
        self.assertEqual(len(outcome.scratch_dirs), len(cli.MACHINE_TYPES))

    def test_command_test_requires_chezmoi_for_shell_templates(self):
        shell_runs = []

        def fake_which(name):
            return None if name == "chezmoi" else f"/bin/{name}"

        def fake_run(args, **kwargs):
            if args[0] == "/bin/zsh":
                shell_runs.append(tuple(args))
            return subprocess.CompletedProcess(args, 0, "", "")

        outcome = self.run_command_test_for_template(fake_run, fake_which)

        self.assertEqual(outcome.result, 1)
        self.assertIn("chezmoi not found", outcome.stderr)
        self.assertEqual(shell_runs, [])

    def test_command_test_reports_missing_template_data(self):
        renders = []

        def fake_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                renders.append(Path(args[args.index("--config") + 1]).stem)
                return subprocess.CompletedProcess(args, 0, b"print ok\n", b"")
            return subprocess.CompletedProcess(args, 0, "", "")

        outcome = self.run_command_test_for_template(fake_run, machines=("personal",))

        self.assertEqual(outcome.result, 1)
        self.assertIn(
            "template render (dot_zshrc.tmpl for work): "
            f"{cli.CHEZMOI_TEST_DATA_DIR / 'work.toml'} not found",
            outcome.stderr,
        )
        self.assertEqual(renders, ["personal"])

    def check_template_with_bash(self, rendered):
        """Run check_shell_template with a fake chezmoi that renders `rendered`.

        The syntax check is a real bash -n. Returns the failed checks, the bytes
        bash was given to check, and what was printed to stderr.
        """
        bash = shutil.which("bash")
        if bash is None:
            self.skipTest("bash is not installed")
        real_run = subprocess.run
        checked = []

        def fake_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                return subprocess.CompletedProcess(args, 0, rendered, b"")
            checked.append(Path(args[-1]).read_bytes())
            return real_run(args, **kwargs)

        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            template = self.make_template_repo(root)
            with (
                mock.patch("shutil.which", return_value="/bin/chezmoi"),
                mock.patch("subprocess.run", side_effect=fake_run),
                mock.patch("sys.stderr", new=io.StringIO()) as stderr,
            ):
                failures = cli.check_shell_template(root, template, bash)

        return failures, checked, stderr.getvalue()

    def test_check_shell_template_fails_a_render_with_crlf_line_endings(self):
        rendered = b"if true; then\r\n  echo hi\r\nfi\r\n"

        failures, checked, _ = self.check_template_with_bash(rendered)

        self.assertCountEqual(
            failures, [f"dot_zshrc.tmpl for {m}" for m in cli.MACHINE_TYPES]
        )
        # bash is given the carriage returns, as it is by the file chezmoi writes.
        self.assertEqual(checked, [rendered] * len(cli.MACHINE_TYPES))

    def test_check_shell_template_passes_bytes_that_are_not_utf8_to_the_shell(self):
        rendered = b"# caf\xe9\necho ok\n"

        failures, checked, _ = self.check_template_with_bash(rendered)

        self.assertEqual(failures, [])
        self.assertEqual(checked, [rendered] * len(cli.MACHINE_TYPES))

    def test_check_shell_template_names_the_template_when_shell_output_is_not_utf8(
        self,
    ):
        # bash echoes the offending line back, byte included.
        failures, _, stderr = self.check_template_with_bash(b"echo caf\xe9 )\n")

        self.assertCountEqual(
            failures, [f"dot_zshrc.tmpl for {m}" for m in cli.MACHINE_TYPES]
        )
        self.assertIn("shell syntax (dot_zshrc.tmpl for work): failed", stderr)
        self.assertIn("caf�", stderr)

    def test_command_test_names_the_template_when_render_error_is_not_utf8(self):
        def fake_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                return subprocess.CompletedProcess(args, 1, b"", b"bad byte \xe9 here")
            return subprocess.CompletedProcess(args, 0, "", "")

        outcome = self.run_command_test_for_template(fake_run)

        self.assertEqual(outcome.result, 1)
        self.assertIn(
            "template render (dot_zshrc.tmpl for work): failed (exit 1)", outcome.stderr
        )
        self.assertIn("bad byte � here", outcome.stderr)

    def test_chezmoi_test_data_type_matches_its_file_name(self):
        import tomllib

        for machine in cli.MACHINE_TYPES:
            with self.subTest(machine=machine):
                data_file = ROOT / cli.CHEZMOI_TEST_DATA_DIR / f"{machine}.toml"
                config = tomllib.loads(data_file.read_text(encoding="utf-8"))
                # The type selects which branches of the templates are rendered.
                self.assertEqual(config["data"]["type"], machine)

    def test_run_lint_shell_targets_runs_available_tools(self):
        repo_root = Path("/repo")
        target = repo_root / "scripts" / "check.sh"
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
            mock.patch("shutil.which", side_effect=fake_which),
            mock.patch("subprocess.run", side_effect=fake_run),
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()),
        ):
            result = cli.run_lint_shell_targets(repo_root, [target])

        self.assertEqual(result, 0)
        self.assertEqual(
            calls,
            [
                ("/opt/homebrew/bin/shfmt", "-w", "scripts/check.sh"),
                ("/opt/homebrew/bin/shellcheck", "scripts/check.sh"),
            ],
        )

    def test_run_lint_shell_targets_skips_when_tools_missing(self):
        repo_root = Path("/repo")
        target = repo_root / "scripts" / "check.sh"

        with (
            mock.patch("shutil.which", return_value=None),
            mock.patch("subprocess.run") as run,
            mock.patch("sys.stdout", new=io.StringIO()),
            mock.patch("sys.stderr", new=io.StringIO()),
        ):
            result = cli.run_lint_shell_targets(repo_root, [target])

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

    def assert_followed_by(self, args, token, expected):
        self.assertIn(token, args)
        index = args.index(token)
        self.assertEqual(args[index + 1 : index + 2], [expected])

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
        self.assertEqual(len(calls), 1)
        args = calls[0][0]
        self.assertEqual(args[0], "/nix/var/nix/profiles/default/bin/nix")
        self.assert_followed_by(args, "profile", "upgrade")
        self.assert_followed_by(args, "--profile", str(profile_path))
        self.assertIn("cli", args)

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
        args = calls[0][0]
        self.assertEqual(args[0], "/nix/var/nix/profiles/default/bin/nix")
        self.assert_followed_by(args, "profile", "add")
        self.assert_followed_by(args, "--profile", str(profile_path))
        self.assertIn(".#cli", args)

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
                    "prod-errors": cli.WorkTool(
                        repo="git@example.com:prod-errors.git",
                        path=tool_path,
                    )
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
                    "prod-errors": cli.WorkTool(
                        repo="git@example.com:prod-errors.git",
                        path=tool_path,
                    )
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
                    "prod-errors": cli.WorkTool(
                        repo="git@example.com:prod-errors.git",
                        path=tool_path,
                    )
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
                    "prod-errors": cli.WorkTool(
                        repo="git@example.com:prod-errors.git",
                        path=Path("/tmp/prod-errors"),
                    )
                },
            ),
            mock.patch.object(Path, "exists", return_value=False),
        ):
            with self.assertRaises(RuntimeError):
                cli.command_work_tools_apply(SimpleNamespace(name="prod-errors"))

    def test_command_work_tools_rejects_unknown_name(self):
        with self.assertRaises(RuntimeError):
            cli.command_work_tools_apply(SimpleNamespace(name="unknown"))

    def test_read_first_line_returns_empty_for_unreadable_and_binary_files(self):
        path = Path("/tmp/unreadable")
        with mock.patch.object(Path, "open", side_effect=PermissionError):
            self.assertEqual(cli.read_first_line(path), "")

        with tempfile.TemporaryDirectory() as tmpdir:
            binary = Path(tmpdir) / "logo.png"
            binary.write_bytes(b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\xff\xfe\xfd")

            self.assertEqual(cli.read_first_line(binary), "")


if __name__ == "__main__":
    unittest.main()
