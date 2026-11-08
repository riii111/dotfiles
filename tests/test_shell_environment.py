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

    def run_zsh(self, command, extra_env=None):
        return subprocess.check_output(
            [
                shutil.which("zsh"),
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
                **(extra_env or {}),
            },
            text=True,
        ).splitlines()

    def test_repeated_path_setup_keeps_tool_precedence(self):
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
        output = self.run_zsh(
            "MANPATH=/custom/man:; INFOPATH=/custom/info; "
            "_dotfiles_homebrew_env prepend; _dotfiles_place_nix_path; "
            "_dotfiles_homebrew_env; _dotfiles_place_nix_path; "
            "whence -p cargo cargo-custom rustc; "
            'print -rl -- "$PATH" "$MANPATH" "$INFOPATH"'
        )
        self.assertEqual(
            output[:3],
            [
                str(self.cargo / "cargo"),
                str(self.cargo / "cargo-custom"),
                str(self.project / "rustc"),
            ],
        )
        paths, manpath, infopath = output[3].split(":"), output[4], output[5]
        self.assertEqual(len(paths), len(set(paths)))
        order = [
            str(self.project),
            str(self.cargo),
            str(self.profile / "bin"),
            "/opt/homebrew/bin",
            "/usr/bin",
        ]
        self.assertEqual([path for path in paths if path in order], order)
        if (
            "/run/current-system/sw/bin" in paths
            and "/nix/var/nix/profiles/default/bin" in paths
        ):
            self.assertLess(
                paths.index("/run/current-system/sw/bin"),
                paths.index("/nix/var/nix/profiles/default/bin"),
            )
        self.assertEqual(manpath.split(":").count("/opt/homebrew/share/man"), 1)
        self.assertEqual(infopath.split(":").count("/opt/homebrew/share/info"), 1)

    def test_managed_ca_bundle_and_curl_are_exported_only_when_present(self):
        command = (
            'print -rl -- "${HOMEBREW_CURL_PATH-unset}" "${SSL_CERT_FILE-unset}" '
            '"${NIX_SSL_CERT_FILE-unset}" "${CURL_CA_BUNDLE-unset}" '
            '"${REQUESTS_CA_BUNDLE-unset}" "${PIP_CERT-unset}"'
        )
        self.assertEqual(self.run_zsh(command), ["unset"] * 6)
        bundle = self.profile / "share/dotfiles/ca-bundle.crt"
        bundle.touch()
        curl = self.profile / "bin/curl"
        curl.write_text("#!/bin/sh\nexit 0\n")
        curl.chmod(0o755)
        self.assertEqual(self.run_zsh(command), [str(curl)] + [str(bundle)] * 5)

    def test_harnexus_call_socket_is_on_unless_already_set(self):
        command = 'print -r -- "$HARNEXUS_CALL_SOCKET"'
        self.assertEqual(self.run_zsh(command), ["on"])
        for value in ("/custom/call.sock", "off"):
            self.assertEqual(
                self.run_zsh(command, {"HARNEXUS_CALL_SOCKET": value}), [value]
            )
