import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("zsh"), "zsh is not installed")
class ShellEnvironmentTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = Path(directory.name)
        self.profile = self.home / ".nix-profile"
        self.cargo = self.home / ".cargo/bin"
        self.project = self.home / "project/bin"
        for path in (
            self.profile / "bin",
            self.profile / "share/dotfiles",
            self.cargo,
            self.project,
        ):
            path.mkdir(parents=True)

    def run_zsh(self, command):
        return subprocess.check_output(
            [
                "zsh",
                "-f",
                "-c",
                'source "$1"; ' + command,
                "zsh",
                str(ROOT / "dot_zshenv"),
            ],
            env={
                "HOME": str(self.home),
                "PATH": os.pathsep.join(
                    map(str, (self.project, self.cargo, "/usr/bin", "/bin"))
                ),
            },
            text=True,
        ).splitlines()

    def test_project_overrides_and_cargo_tools_keep_precedence(self):
        for directory, name in (
            (self.cargo, "cargo-custom"),
            (self.profile / "bin", "rustup"),
            (self.project, "rustc"),
        ):
            executable = directory / name
            executable.write_text("#!/bin/sh\nexit 0\n")
            executable.chmod(0o755)
        (self.cargo / "rustup").symlink_to(self.profile / "bin/rustup")
        (self.cargo / "cargo").symlink_to("rustup")
        self.assertEqual(
            self.run_zsh("whence -p cargo cargo-custom rustc"),
            [
                str(self.cargo / "cargo"),
                str(self.cargo / "cargo-custom"),
                str(self.project / "rustc"),
            ],
        )

    def test_repeated_path_setup_keeps_active_system_before_installer_nix(self):
        paths = self.run_zsh('_dotfiles_place_nix_path; print -rl -- "${path[@]}"')
        self.assertEqual(len(paths), len(set(paths)))
        self.assertLess(paths.index(str(self.project)), paths.index(str(self.cargo)))
        self.assertLess(paths.index(str(self.profile / "bin")), paths.index("/usr/bin"))
        if (
            "/run/current-system/sw/bin" in paths
            and "/nix/var/nix/profiles/default/bin" in paths
        ):
            self.assertLess(
                paths.index("/run/current-system/sw/bin"),
                paths.index("/nix/var/nix/profiles/default/bin"),
            )

    def test_clients_share_the_managed_ca_bundle(self):
        bundle = self.profile / "share/dotfiles/ca-bundle.crt"
        bundle.touch()
        self.assertEqual(
            self.run_zsh(
                'print -rl -- "$SSL_CERT_FILE" "$NIX_SSL_CERT_FILE" "$CURL_CA_BUNDLE" "$REQUESTS_CA_BUNDLE" "$PIP_CERT"'
            ),
            [str(bundle)] * 5,
        )

    def test_homebrew_uses_managed_curl_when_available(self):
        curl = self.profile / "bin/curl"
        curl.write_text("#!/bin/sh\nexit 0\n")
        curl.chmod(0o755)
        self.assertEqual(self.run_zsh('print -r -- "$HOMEBREW_CURL_PATH"'), [str(curl)])

    def test_missing_managed_curl_does_not_set_broken_homebrew_path(self):
        self.assertEqual(
            self.run_zsh('print -r -- "${HOMEBREW_CURL_PATH-unset}"'), ["unset"]
        )
