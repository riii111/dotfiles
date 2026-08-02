#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/dot_codex/hooks/executable_permission_request.py"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-permission-hook-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
git -C "$tmpdir" init -q
git -C "$tmpdir" switch -q -c feat/test
git -C "$tmpdir" config branch.feat/test.remote origin
git -C "$tmpdir" config branch.feat/test.merge refs/heads/feat/test

run_hook() {
	local command="$1"
	jq -n --arg cwd "$tmpdir" --arg command "$command" '{cwd:$cwd,tool_input:{command:$command}}' |
		python3 "$hook"
}

run_hook 'git push' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
run_hook 'git push -u origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
test -z "$(run_hook 'git push --force origin HEAD')"

git -C "$tmpdir" switch -q -c feat/no-upstream
test -z "$(run_hook 'git push')"

git -C "$tmpdir" switch -q -c main
git -C "$tmpdir" config branch.main.remote origin
git -C "$tmpdir" config branch.main.merge refs/heads/main
test -z "$(run_hook 'git push')"

printf 'codex permission hook tests passed\n'
