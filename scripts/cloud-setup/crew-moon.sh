#!/usr/bin/env bash
# Prepares the pinned harnexus-crew toolchain inside the setup's staging directory.
set -euo pipefail

root=$1
if [[ $(uname -sm) != 'Linux x86_64' ]]; then
	echo 'cloud-setup: the harnexus-crew MoonBit toolchain requires Linux x86_64' >&2
	exit 1
fi
release='https://github.com/moonbit-community/moonbit-overlay/releases/download/v0.10.20%2B65efd5b93%2B940aa18'
mkdir -p "$root/download" "$root/toolchain/lib"
curl -fsSL --retry 3 -o "$root/download/moon.tar.gz" "$release/moonbit-linux-x86_64.tar.gz"
curl -fsSL --retry 3 -o "$root/download/core.tar.gz" "$release/moonbit-core.tar.gz"
printf '%s  %s\n' '80d987523308fa490eba9f1baf98df996a5a7891e118357553b7c2608c0597c5' "$root/download/moon.tar.gz" | sha256sum -c --quiet
printf '%s  %s\n' '8ec2a2c01335501d703867bb4eef5f92d3cd7e1ae1ee5f7f14d54d16d2c7c2b5' "$root/download/core.tar.gz" | sha256sum -c --quiet
tar xzf "$root/download/moon.tar.gz" -C "$root/toolchain"
tar xzf "$root/download/core.tar.gz" -C "$root/toolchain/lib"
chmod +x "$root/toolchain"/bin/* "$root/toolchain/bin/internal/tcc"
export MOON_TOOLCHAIN_ROOT="$root/toolchain"
export PATH="$root/toolchain/bin:$PATH"
moon -C "$root/toolchain/lib/core" bundle --warn-list -a --target native
