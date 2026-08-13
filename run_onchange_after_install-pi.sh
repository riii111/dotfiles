#!/bin/sh
set -eu

version="0.81.1"

if command -v pi >/dev/null 2>&1 && [ "$(pi --version)" = "$version" ]; then
	exit 0
fi

npm install --global --prefix "${HOME}/.local" "@earendil-works/pi-coding-agent@${version}"
