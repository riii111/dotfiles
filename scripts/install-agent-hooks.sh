#!/usr/bin/env bash
# Builds agent-hooks into the given folder for a Claude Code cloud environment, which has no Nix.
# The MoonBit release, its core library and the async package are pinned by version and SHA-256; keep them in sync with
# nix/moonbit.nix and agent-hooks/package.nix.
set -euo pipefail

dest=$1
source_dir=$(cd "$(dirname "$0")/../agent-hooks" && pwd)

if [[ $(uname -sm) != "Linux x86_64" ]]; then
	echo "install-agent-hooks: only Linux x86_64 is supported" >&2
	exit 1
fi

# cloud-setup runs again at each session start, so the binary is rebuilt only after its sources or this script's pins change.
stamp="$dest/.agent-hooks.src-hash"
source_hash=$({
	sha256sum <"$0"
	cd "$source_dir" && find . -type f ! -path './_build/*' ! -path './.mooncakes/*' -print0 | sort -z | xargs -0 sha256sum
} | sha256sum | cut -d' ' -f1)
if [[ -x $dest/agent-hooks && $(cat "$stamp" 2>/dev/null) == "$source_hash" ]]; then
	exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
download() {
	curl -fsSL --retry 3 -o "$work/$1" "$2"
	echo "$3  $work/$1" | sha256sum -c --quiet
}
version=0.10.17%2Bd971670cd
download moonbit.tar.gz "https://cli.moonbitlang.com/binaries/$version/moonbit-linux-x86_64.tar.gz" \
	d0a96eaf91c77cfcdd7b7df75390c5a1a95d0b8a328b1a5ed6fee050cfbf8d50
download core.tar.gz "https://cli.moonbitlang.com/cores/core-$version.tar.gz" \
	2d837ecbef5933c09726d63682a7695123d622e6aee13525fbc98c4b49433714
download async.zip https://download.mooncakes.io/user/moonbitlang/async/0.22.5.zip \
	142776b3fac385b8ee97e62fb3213b02a80595ae1a4a80ede6419f452eab01c2

export MOON_HOME="$work/moon"
export PATH="$MOON_HOME/bin:$PATH"
mkdir -p "$MOON_HOME"
tar xzf "$work/moonbit.tar.gz" -C "$MOON_HOME"
# The archive drops the executable bits that the official installer sets again.
chmod +x "$MOON_HOME"/bin/* "$MOON_HOME/bin/internal/tcc"
tar xzf "$work/core.tar.gz" -C "$MOON_HOME/lib"
moon -C "$MOON_HOME/lib/core" bundle --warn-list -a --target native

# moon resolves registry dependencies through the index even when the archive is cached, so it gets an index with only the pinned entry.
mkdir -p "$MOON_HOME/registry/index/user/moonbitlang" "$MOON_HOME/registry/cache/moonbitlang/async"
printf '%s\n' '{"checksum":"142776b3fac385b8ee97e62fb3213b02a80595ae1a4a80ede6419f452eab01c2","name":"moonbitlang/async","preferred_target":"native","source":"src","version":"0.22.5"}' \
	>"$MOON_HOME/registry/index/user/moonbitlang/async.index"
cp "$work/async.zip" "$MOON_HOME/registry/cache/moonbitlang/async/0.22.5.zip"

cp -R "$source_dir" "$work/src"
rm -rf "$work/src/_build" "$work/src/.mooncakes"
moon -C "$work/src" build --release --target native
# A hook that starts during a background refresh must never find the binary missing or half written.
install -m 0755 "$work/src/_build/native/release/build/cmd/main/main.exe" "$dest/.agent-hooks.new"
mv -f "$dest/.agent-hooks.new" "$dest/agent-hooks"
echo "$source_hash" >"$stamp"
