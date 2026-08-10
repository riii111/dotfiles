#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-wrapper-test.XXXXXX")"
test_home="$test_root/home"
repo="$test_home/ghq/github.com/riii111/test"
remote="$test_root/remote.git"
skill="$test_home/.codex/skills/demo"
plugin_skill="$test_home/.codex/plugins/cache/openai-bundled/demo/1.0.0/skills"
outside="$test_root/outside.txt"
read_lines="$repo_root/bin/executable_codex-read-lines"
force_with_lease="$repo_root/bin/executable_codex-force-with-lease"
runner="$repo_root/tests/run-codex-python-with-home.py"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$repo" "$skill" "$plugin_skill"
git init -q --bare "$remote"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" remote add origin https://github.com/riii111/test.git
printf 'one\ntwo\nthree\n' >"$repo/file.txt"
printf 'skill one\nskill two\n' >"$skill/SKILL.md"
printf 'plugin skill one\nplugin skill two\n' >"$plugin_skill/SKILL.md"
printf 'outside\n' >"$outside"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m initial
git -C "$repo" branch -M main
git -C "$repo" switch -q -c feat/test
printf 'four\n' >>"$repo/file.txt"
git -C "$repo" add file.txt
git -C "$repo" commit -q -m update

run_read_lines() {
	(cd "$repo" && HOME="$test_home" python3 "$runner" "$read_lines" "$test_home" "$@")
}

run_skill_escape() {
	(cd "$test_home" && HOME="$test_home" python3 "$runner" "$read_lines" "$test_home" 1 1 \
		"$test_home/.codex/skills/../outside.txt")
}

run_force() {
	(cd "$repo" && HOME="$test_home" python3 "$runner" "$force_with_lease" "$test_home" "$@")
}

expect_failure() {
	if "$@" >/dev/null 2>&1; then
		printf 'command unexpectedly succeeded: %s\n' "$*" >&2
		return 1
	fi
}

test "$(run_read_lines 2 3 file.txt)" = $'two\nthree'
skill_output="$(cd "$test_home" && HOME="$test_home" python3 "$runner" "$read_lines" "$test_home" 1 2 "$skill/SKILL.md")"
test "$skill_output" = $'skill one\nskill two'
plugin_skill_output="$(run_read_lines 1 2 "$plugin_skill/SKILL.md")"
test "$plugin_skill_output" = $'plugin skill one\nplugin skill two'
expect_failure run_read_lines 1 1 "$test_home/.codex/plugins/cache/openai-bundled/demo/SKILL.md"
test "$(run_read_lines 1 1 ../test/file.txt)" = one
mkdir -p "$test_home/.ssh"
printf 'Host work-github\n  HostName github.com\n' >"$test_home/.ssh/config"
git -C "$repo" remote set-url origin https://work-github/riii111/test.git
expect_failure run_read_lines 2 3 file.txt
git -C "$repo" remote set-url origin https://github.com/riii111/test.git
printf 'Host work-github\n  HostName github.com\n' >"$test_home/.ssh/config"
git -C "$repo" config url."file://$remote".insteadOf https://github.com/riii111/test.git
expect_failure run_read_lines 2 3 file.txt
git -C "$repo" config --unset-all url."file://$remote".insteadOf
expect_failure run_read_lines 0 1 file.txt
expect_failure run_read_lines 2 1 file.txt
expect_failure run_read_lines 1 1 "$outside"
ln -s "$outside" "$repo/escape.txt"
expect_failure run_read_lines 1 1 escape.txt
ln -s "$outside" "$plugin_skill/escape.txt"
expect_failure run_read_lines 1 1 "$plugin_skill/escape.txt"
expect_failure run_skill_escape

expect_failure run_force unexpected
expect_failure run_force

git -C "$repo" remote set-url origin https://example.com/riii111/test.git
expect_failure run_force

printf 'codex wrapper tests passed\n'
