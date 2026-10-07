#!/usr/bin/env bash
set -euo pipefail

if ! command -v kitty >/dev/null 2>&1; then
	echo "kitty herdr mode test: skipped (kitty not installed)"
	exit 0
fi

repo_root="$(git rev-parse --show-toplevel)"
test_path="$repo_root/tests/kitty_herdr_mode_test.py"
# kitty runs embedded Python with -OO, which strips every assert; compile the test with optimization off.
kitty +runpy "import sys; path = sys.argv[1]; exec(compile(open(path).read(), path, 'exec', optimize=0), {'__name__': '__main__', '__file__': path})" "$test_path"
