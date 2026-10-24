#!/bin/sh
set -eu

repo="${HOME}/ghq/github.com/riii111/agents-retro"
install_root="${HOME}/.local"

[ -d "$repo" ] || exit 0
command -v nix >/dev/null 2>&1 || exit 0

nix develop "$repo" --command moon -C "$repo" build --target native --release
mkdir -p "${install_root}/bin"
install -m 755 "${repo}/_build/native/release/build/cmd/main/main.exe" "${install_root}/bin/agents-retro"
