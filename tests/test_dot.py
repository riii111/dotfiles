import shutil
import subprocess
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest import mock

from bin.lib.dot import cli


ROOT = Path(__file__).resolve().parents[1]


class ShellDetectionTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)

    def write(self, name, text="# comment\n"):
        path = self.root / name
        path.write_text(text, encoding="utf-8")
        return path

    def test_detect_shell_uses_shebang_and_skips_other_languages(self):
        self.assertEqual(
            cli.detect_shell(self.write("script", "#!/usr/bin/env bash\n")), "bash"
        )
        self.assertEqual(
            cli.detect_shell(self.write("strict", "#!/usr/bin/env -S bash -eu\n")),
            "bash",
        )
        self.assertIsNone(
            cli.detect_shell(self.write("tool", "#!/usr/bin/env python3\n"))
        )
        self.assertIsNone(
            cli.detect_shell(self.write("fish_tool", "#!/usr/bin/env fish\n"))
        )

    def test_detect_shell_classifies_templates_by_the_file_they_render_to(self):
        self.assertEqual(cli.detect_shell(self.write("dot_zshrc.tmpl")), "zsh")
        self.assertEqual(cli.detect_shell(self.write("hook.zsh.tmpl")), "zsh")
        self.assertEqual(cli.detect_shell(self.write("install.sh.tmpl")), "bash")
        self.assertIsNone(cli.detect_shell(self.write("config.toml.tmpl")))

    def test_detect_shell_treats_zsh_startup_files_as_zsh(self):
        self.assertEqual(cli.detect_shell(self.write("dot_zshenv")), "zsh")
        self.assertIsNone(cli.detect_shell(self.write("dot_psqlrc")))

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

    def test_fails_a_render_with_crlf_line_endings(self):
        failures, _, _ = self.check_template(
            lambda machine: (0, b"if true; then\r\n  echo hi\r\nfi\r\n")
        )

        self.assertCountEqual(
            failures, [f"dot_zshrc.tmpl for {m}" for m in cli.MACHINE_TYPES]
        )

    def test_skips_the_syntax_check_of_a_failed_render(self):
        failures, _, checked = self.check_template(
            lambda machine: (1, b"") if machine == "work" else (0, b"echo ok\n")
        )

        self.assertEqual(failures, ["dot_zshrc.tmpl for work"])
        self.assertEqual(checked, ["dot_zshrc.personal"])

    def test_fails_a_machine_type_without_test_data(self):
        failures, render_envs, _ = self.check_template(
            lambda machine: (0, b"echo ok\n"), machines=("personal",)
        )

        self.assertEqual(failures, ["dot_zshrc.tmpl for work"])
        self.assertEqual(set(render_envs), {"personal"})

    def test_chezmoi_test_data_type_matches_its_file_name(self):
        for machine in cli.MACHINE_TYPES:
            with self.subTest(machine=machine):
                data_file = ROOT / cli.CHEZMOI_TEST_DATA_DIR / f"{machine}.toml"
                config = tomllib.loads(data_file.read_text(encoding="utf-8"))
                # The type selects which branches of the templates are rendered.
                self.assertEqual(config["data"]["type"], machine)


if __name__ == "__main__":
    unittest.main()
