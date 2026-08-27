#!/usr/bin/env bash
set -euo pipefail

if ! command -v kitty >/dev/null 2>&1; then
	echo "kitty herdr mode test: skipped (kitty not installed)"
	exit 0
fi

repo_root="$(git rev-parse --show-toplevel)"
test_path="$repo_root/tests/kitty_herdr_mode_test.py"
kitty +runpy "import runpy; runpy.run_path('$test_path', run_name='__main__')"
