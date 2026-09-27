#!/usr/bin/env python3
"""Check or update plugins in disposable XDG directories."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "update"))
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    source = repo / "private_dot_config/nvim"
    lockfile = source / "lazy-lock.json"
    original = lockfile.read_bytes()
    required = (
        "nvim",
        "git",
        "make",
        "cc",
        "go",
        "rg",
        "tree-sitter",
        "lua-language-server",
    )
    missing = [command for command in required if not shutil.which(command)]
    if missing:
        parser.error("Missing commands: " + ", ".join(missing))

    with tempfile.TemporaryDirectory(prefix="dotfiles-nvim-") as directory:
        root = Path(directory)
        env = {
            name: os.environ[name]
            for name in (
                "PATH",
                "HOME",
                "TMPDIR",
                "LANG",
                "LC_ALL",
                "RUNNER_TEMP",
                "SSL_CERT_FILE",
                "NIX_SSL_CERT_FILE",
                "NIX_PROFILES",
                "HTTPS_PROXY",
                "HTTP_PROXY",
                "NO_PROXY",
                "ALL_PROXY",
                "https_proxy",
                "http_proxy",
                "no_proxy",
                "all_proxy",
            )
            if name in os.environ
        }
        for name in ("CONFIG", "DATA", "STATE", "CACHE"):
            env[f"XDG_{name}_HOME"] = str(root / name.lower())
        env["XDG_CONFIG_DIRS"] = str(root / "config-dirs")
        env["XDG_DATA_DIRS"] = str(root / "data-dirs")
        env["NVIM_APPNAME"] = "nvim"
        env["DOTFILES_NVIM_TESTS"] = str(repo / "tests/nvim")
        config = root / "config/nvim"
        shutil.copytree(source, config)
        lazy = root / "data/nvim/lazy/lazy.nvim"
        lazy.parent.mkdir(parents=True)

        def run(command):
            subprocess.run(command, cwd=root, env=env, check=True, timeout=900)

        run(
            [
                "git",
                "clone",
                "--filter=blob:none",
                "https://github.com/folke/lazy.nvim.git",
                str(lazy),
            ]
        )
        run(
            [
                "git",
                "-C",
                str(lazy),
                "checkout",
                "--detach",
                json.loads(original)["lazy.nvim"]["commit"],
            ]
        )
        mason_bin = root / "data/nvim/mason/bin"
        mason_bin.mkdir(parents=True)
        (mason_bin / "lua-language-server").symlink_to(
            shutil.which("lua-language-server")
        )
        fixture = root / "fixture"
        fixture.mkdir()
        (fixture / "sample.lua").write_text(
            'local answer = string.len("hello")\nprint(answer)\n'
        )
        env["DOTFILES_NVIM_FIXTURE"] = str(fixture)

        def nvim(mode):
            env["DOTFILES_NVIM_MODE"] = mode
            run(
                [
                    "nvim",
                    "--headless",
                    "-i",
                    "NONE",
                    "--cmd",
                    'lua dofile(vim.env.DOTFILES_NVIM_TESTS .. "/capture.lua")',
                    "-c",
                    'lua dofile(vim.env.DOTFILES_NVIM_TESTS .. "/run.lua")',
                ]
            )

        nvim("check")
        installed = json.loads((config / "lazy-lock.json").read_bytes())
        # Upstream may rename its default branch without changing the locked commit.
        if {name: entry["commit"] for name, entry in json.loads(original).items()} != {
            name: entry["commit"] for name, entry in installed.items()
        }:
            raise RuntimeError(
                "Installing the locked plugins changed the recorded commits"
            )
        if args.mode == "update":
            nvim("update")
            nvim("check")
            if lockfile.read_bytes() != original:
                raise RuntimeError(
                    "Source lockfile changed during verification; refusing to overwrite it"
                )
            lockfile.write_bytes((config / "lazy-lock.json").read_bytes())
    print(f"Neovim plugin {args.mode}: OK")


if __name__ == "__main__":
    main()
