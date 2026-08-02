#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/dot_codex/hooks/executable_permission_request.py"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-permission-hook-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
git -C "$tmpdir" init -q
git -C "$tmpdir" switch -q -c feat/test
git -C "$tmpdir" remote add origin https://github.com/riii111/test.git

run_hook() {
	local command="$1"
	jq -n --arg cwd "$tmpdir" --arg command "$command" '{cwd:$cwd,tool_input:{command:$command}}' |
		python3 "$hook"
}

run_hook 'git push -u origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
run_hook 'git push origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
run_hook 'git push --set-upstream origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
run_hook 'gh auth status' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
test -z "$(run_hook 'gh auth status --show-token')"
test -z "$(run_hook 'gh auth status --hostname github.com')"
test -z "$(run_hook 'git push')"
test -z "$(run_hook 'git push origin feat/test')"
test -z "$(run_hook 'git push --force origin HEAD')"

git -C "$tmpdir" remote set-url origin https://example.com/riii111/test.git
test -z "$(run_hook 'git push origin HEAD')"

git -C "$tmpdir" remote set-url origin git@github.com:riii111/test.git
run_hook 'git push origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null

git -C "$tmpdir" remote set-url --add --push origin https://github.com/riii111/test.git
git -C "$tmpdir" remote set-url --add --push origin https://example.com/riii111/test.git
test -z "$(run_hook 'git push origin HEAD')"

git -C "$tmpdir" switch -q -c main
test -z "$(run_hook 'git push origin HEAD')"

printf 'codex permission hook tests passed\n'
