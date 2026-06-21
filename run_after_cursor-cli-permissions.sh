#!/bin/sh
set -eu

src="${HOME}/.cursor/cli-config.json"
dst="${HOME}/.config/cursor/cli-config.json"

[ -f "$src" ] || exit 0

mkdir -p "$(dirname "$dst")"
tmp="$(mktemp)"

if [ -f "$dst" ]; then
	jq --slurpfile src "$src" '.permissions = $src[0].permissions' "$dst" >"$tmp"
else
	jq '{permissions: .permissions}' "$src" >"$tmp"
fi

mv "$tmp" "$dst"
