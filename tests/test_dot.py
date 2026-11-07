import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli


class ShellDetectionTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def write(self, name, text="# comment\n"):
        path = self.root / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_detect_shell(self):
        for name, text, expected in (
            ("script", "#!/usr/bin/env bash\n", "bash"),
            ("strict", "#!/usr/bin/env -S bash -eu\n", "bash"),
            ("tool", "#!/usr/bin/env python3\n", None),
            ("fish_tool", "#!/usr/bin/env fish\n", None),
            # A template is classified by the file it renders to.
            ("dot_zshrc.tmpl", "# comment\n", "zsh"),
            ("hook.zsh.tmpl", "# comment\n", "zsh"),
            ("install.sh.tmpl", "# comment\n", "bash"),
            ("config.toml.tmpl", "# comment\n", None),
            ("dot_zshenv", "# comment\n", "zsh"),
            ("dot_psqlrc", "# comment\n", None),
        ):
            with self.subTest(name=name):
                self.assertEqual(cli.detect_shell(self.write(name, text)), expected)

    def test_lint_targets_exclude_zsh_and_templates(self):
        bash_script = self.write("check.sh", "#!/usr/bin/env bash\n")
        zsh_script = self.write("hook.zsh", "#!/bin/zsh\n")
        # shfmt -w would rewrite the actions of a bash template.
        bash_template = self.write("install.sh.tmpl", "#!/bin/bash\n{{ end }}\n")

        targets = cli.collect_lintable_shell_targets(
            [bash_script, zsh_script, bash_template]
        )

        self.assertEqual(targets, [bash_script])


class ShellTemplateTest(unittest.TestCase):
    def check_template(self, render, machines=cli.MACHINE_TYPES):
        """Run check_shell_template with a fake chezmoi and a real bash -n.

        `render` maps a machine type to (exit code, rendered bytes). Returns the
        failed checks, the environment of each render, and the names of the
        rendered files that bash was given.
        """
        bash = shutil.which("bash")
        if bash is None:
            self.skipTest("bash is not installed")
        real_run = subprocess.run
        render_envs = {}
        checked = []

        def fake_run(args, **kwargs):
            if args[0] == "/bin/chezmoi":
                machine = Path(args[args.index("--config") + 1]).stem
                render_envs[machine] = kwargs["env"]
                code, output = render(machine)
                return subprocess.CompletedProcess(args, code, output, b"")
            checked.append(Path(args[-1]).name)
            return real_run(args, **kwargs)

        with tempfile.TemporaryDirectory() as tmpdir:
            root = Path(tmpdir)
            data_dir = root / cli.CHEZMOI_TEST_DATA_DIR
            data_dir.mkdir(parents=True)
            for machine in machines:
                (data_dir / f"{machine}.toml").write_text(
                    f'[data]\ntype = "{machine}"\n', encoding="utf-8"
                )
            template = root / "dot_zshrc.tmpl"
            template.write_text('{{ if eq .type "work" }}\n', encoding="utf-8")
            with (
                mock.patch("shutil.which", return_value="/bin/chezmoi"),
                mock.patch("subprocess.run", side_effect=fake_run),
                mock.patch("sys.stderr"),
            ):
                failures = cli.check_shell_template(root, template, bash)

            for env in render_envs.values():
                home = Path(env["HOME"])
                self.assertNotIn(root, home.parents)
                self.assertFalse(home.exists(), f"{home} was left behind")
        return failures, render_envs, checked

    def test_renders_each_machine_type_in_a_throwaway_home(self):
        failures, render_envs, checked = self.check_template(
            lambda machine: (0, b"# caf\xe9\necho ok\n")
        )

        self.assertEqual(failures, [])
        self.assertEqual(set(render_envs), set(cli.MACHINE_TYPES))
        for env in render_envs.values():
            self.assertEqual(set(env), {"PATH", "HOME"})
        self.assertCountEqual(
            checked, [f"dot_zshrc.{machine}" for machine in cli.MACHINE_TYPES]
        )

    def test_reports_each_failing_machine_type(self):
        for name, render, machines, failures, checked in (
            (
                "crlf line endings",
                lambda machine: (0, b"if true; then\r\n  echo hi\r\nfi\r\n"),
                cli.MACHINE_TYPES,
                [f"dot_zshrc.tmpl for {m}" for m in cli.MACHINE_TYPES],
                [f"dot_zshrc.{m}" for m in cli.MACHINE_TYPES],
            ),
            (
                "failed render skips the syntax check",
                lambda machine: (1, b"") if machine == "work" else (0, b"echo ok\n"),
                cli.MACHINE_TYPES,
                ["dot_zshrc.tmpl for work"],
                ["dot_zshrc.personal"],
            ),
            (
                "missing test data",
                lambda machine: (0, b"echo ok\n"),
                ("personal",),
                ["dot_zshrc.tmpl for work"],
                ["dot_zshrc.personal"],
            ),
        ):
            with self.subTest(name):
                actual, _, actual_checked = self.check_template(render, machines)
                self.assertCountEqual(actual, failures)
                self.assertCountEqual(actual_checked, checked)


class OndemandTestsTest(unittest.TestCase):
    def test_rejects_paths_that_are_not_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests/ondemand").mkdir(parents=True)
            (root / "tests/ondemand/helpers.py").write_text("")
            with (
                mock.patch.object(cli.subprocess, "Popen") as popen,
                mock.patch("sys.stderr"),
            ):
                code = cli.run_ondemand_tests(root, ["tests/ondemand/helpers.py"])
            self.assertEqual(code, 1)
            popen.assert_not_called()

    def test_streams_unittest_output_and_fails_on_skips(self):
        cases = (
            ("pass", 0),
            ("self.skipTest('no tool')", 1),
        )
        for body, expected in cases:
            with self.subTest(body), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "tests/ondemand").mkdir(parents=True)
                (root / "tests/ondemand/test_x.py").write_text(
                    "import unittest\n\n\nclass T(unittest.TestCase):\n"
                    f"    def test_x(self):\n        {body}\n"
                )
                with (
                    mock.patch("sys.stderr") as stderr,
                    mock.patch("sys.stdout"),
                ):
                    code = cli.run_ondemand_tests(root, [])
                self.assertEqual(code, expected)
                written = "".join(call.args[0] for call in stderr.write.call_args_list)
                self.assertIn("test_x", written)

    def test_leaves_darwin_tests_out_on_linux_unless_named(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "tests/ondemand").mkdir(parents=True)
            (root / "scripts/ci").mkdir(parents=True)
            (root / "scripts/ci/selection.py").write_text(
                'DARWIN_ONDEMAND = {"test_mac.py"}\n'
            )
            for name in ("test_mac.py", "test_x.py"):
                (root / "tests/ondemand" / name).write_text("")
            for platform, paths, expected, notice in (
                ("linux", [], ["tests/ondemand/test_x.py"], True),
                (
                    "darwin",
                    [],
                    ["tests/ondemand/test_mac.py", "tests/ondemand/test_x.py"],
                    False,
                ),
                (
                    "linux",
                    ["tests/ondemand/test_mac.py"],
                    ["tests/ondemand/test_mac.py"],
                    False,
                ),
            ):
                with (
                    self.subTest(platform=platform, paths=paths),
                    mock.patch.object(cli.sys, "platform", platform),
                    mock.patch.object(cli.subprocess, "Popen") as popen,
                    mock.patch("sys.stderr") as stderr,
                    mock.patch("sys.stdout"),
                ):
                    process = popen.return_value.__enter__.return_value
                    process.stderr = ["OK\n"]
                    process.returncode = 0
                    self.assertEqual(cli.run_ondemand_tests(root, paths), 0)
                    self.assertEqual(popen.call_args.args[0][4:], expected)
                    written = "".join(
                        call.args[0] for call in stderr.write.call_args_list
                    )
                    self.assertEqual("test_mac.py" in written, notice)


if __name__ == "__main__":
    unittest.main()
