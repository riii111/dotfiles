#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/dot_codex/hooks/executable_permission_request.py"
hooks_config="$repo_root/dot_codex/hooks.json"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/codex-permission-hook-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
git -C "$tmpdir" init -q
git -C "$tmpdir" switch -q -c feat/test
git -C "$tmpdir" remote add origin https://github.com/riii111/test.git

run_hook() {
	local event_name="$1"
	local command="$2"
	jq -n --arg cwd "$tmpdir" --arg event_name "$event_name" --arg command "$command" \
		'{cwd:$cwd,hook_event_name:$event_name,tool_input:{command:$command}}' |
		python3 "$hook"
}

jq -e '.hooks.PreToolUse[0].matcher == "^Bash$"' "$hooks_config" >/dev/null

permission_request() { run_hook PermissionRequest "$1"; }
pre_tool_use() { run_hook PreToolUse "$1"; }

permission_request 'git push -u origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git push origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git push --set-upstream origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'gh auth status' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git branch --show-current' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git fetch origin' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
test -z "$(permission_request 'git fetch --force origin')"
test -z "$(permission_request 'git fetch origin +main:main')"
test -z "$(permission_request 'git fetch --update-head-ok origin')"
permission_request 'gh auth status --show-token' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'gh auth status --hostname github.com --show-token' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'gh auth status --hostname github.com -t' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'git reset HEAD~1 --hard' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
test -z "$(permission_request 'gh auth status --hostname github.com')"
test -z "$(permission_request 'git push')"
test -z "$(permission_request 'git push origin feat/test')"

for command in \
	'git reset HEAD~1 --hard' \
	'git add -f ignored' \
	'git clean -fdx' \
	'git gc --prune=now' \
	'git -C repo push origin +main:main' \
	'git push origin :old' \
	'gh auth token' \
	'gh auth status --hostname github.com --show-token' \
	'gh repo delete owner/repo' \
	'gcloud auth print-access-token' \
	'gcloud projects delete project' \
	'terraform apply' \
	'sudo command' \
	'chmod 777 file'; do
	pre_tool_use "$command" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
done
# PreToolUse cannot request approval, so prompt-class operations remain governed by the sandbox.
test -z "$(pre_tool_use 'rm file')"
pre_tool_use '/usr/bin/git reset --hard' | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
pre_tool_use '/bin/rm -rf build' | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null

# Indirection and compound shell syntax are outside this best-effort hook's contract.
for command in \
	"eval 'git reset --hard'" \
	'exec /usr/bin/git reset --hard' \
	'printf build | xargs rm -rf' \
	"find . -exec rm -rf '{}' +" \
	'nice -n 5 /usr/bin/git reset --hard' \
	'command -p git reset --hard' \
	"env -S 'git reset --hard'" \
	'if true; then git reset --hard; fi' \
	"printf 'git reset --hard\\n' | sh" \
	"git -c alias.x='!git reset --hard' x" \
	'nohup git reset --hard'; do
	test -z "$(pre_tool_use "$command")"
done

# Normal shell composition must not interrupt autonomous development work.
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in 'echo "$HOME"' 'git diff "$(git merge-base main HEAD)"' 'rg foo src/*.rs' 'source .venv/bin/activate'; do
	test -z "$(pre_tool_use "$command")"
done

git -C "$tmpdir" remote set-url origin https://example.com/riii111/test.git
test -z "$(permission_request 'git push origin HEAD')"
test -z "$(permission_request 'git fetch origin')"

git -C "$tmpdir" remote set-url origin git@github.com:riii111/test.git
permission_request 'git push origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null

git -C "$tmpdir" remote set-url --add --push origin https://github.com/riii111/test.git
git -C "$tmpdir" remote set-url --add --push origin https://example.com/riii111/test.git
test -z "$(permission_request 'git push origin HEAD')"

git -C "$tmpdir" switch -q -c main
test -z "$(permission_request 'git push origin HEAD')"

printf 'codex permission hook tests passed\n'
