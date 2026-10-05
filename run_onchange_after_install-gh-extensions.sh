#!/bin/sh
set -eu

# repo@tag
extensions="
github/gh-stack@v0.2.0
"

command -v gh >/dev/null 2>&1 || exit 0

installed="$(gh extension list 2>/dev/null || true)"

for entry in $extensions; do
	repo="${entry%@*}"
	tag="${entry#*@}"
	if printf '%s\n' "$installed" | grep -F "$repo" | grep -qF "$tag"; then
		continue
	fi
	gh extension remove "${repo#*/}" >/dev/null 2>&1 || true
	gh extension install "$repo" --pin "$tag"
done
