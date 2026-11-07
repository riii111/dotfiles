#!/usr/bin/env bash
# The cases that depend on a checkout: its trust, branch, configuration and the Git processes the hook starts.
# Commands decided by their text alone are tested in dot-tools/permission.

set -euo pipefail

while IFS= read -r variable; do
	unset "$variable"
done < <(env | sed -n 's/=.*//p' | sed -n '/^GIT_/p')
export GIT_PAGER=cat

# Tests the agent-hooks on PATH; the Nix dev shells build it from this checkout.
hook="${AGENT_HOOKS:-agent-hooks}"
# macOS TMPDIR ends with "/", and the hook compares resolved paths.
tmp_base="${TMPDIR:-/tmp}"
test_root="$(mktemp -d "${tmp_base%/}/codex-permission-hook-test.XXXXXX")"
test_home="$test_root/home"
tmpdir="$test_home/ghq/github.com/riii111/test"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$tmpdir"
git -C "$tmpdir" init -q
git -C "$tmpdir" switch -q -c feat/test
git -C "$tmpdir" remote add origin https://github.com/riii111/test.git

run_hook() {
	local event_name="$1"
	local command="$2"
	HOME="$test_home" jq -n --arg cwd "$tmpdir" --arg event_name "$event_name" --arg command "$command" \
		'{cwd:$cwd,hook_event_name:$event_name,tool_input:{command:$command}}' |
		HOME="$test_home" "$hook" permission-request
}

permission_request() { run_hook PermissionRequest "$1"; }
pre_tool_use() { run_hook PreToolUse "$1"; }
permission_request_with_env() {
	local name="$1"
	local value="$2"
	local command="$3"
	(
		export "$name=$value"
		permission_request "$command"
	)
}

expect_allowed() {
	permission_request "$1" | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
}

expect_denied() {
	permission_request "$1" | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
}

# Silence means exit 0 with empty stdout and stderr, so a crashing hook cannot pass as "no decision".
expect_silent() {
	local status=0
	"$@" >"$test_root/stdout" 2>"$test_root/stderr" || status=$?
	if [ "$status" -ne 0 ] || [ -s "$test_root/stdout" ] || [ -s "$test_root/stderr" ]; then
		printf 'expected a silent success (exit %s): %s\n' "$status" "$*" >&2
		cat "$test_root/stdout" "$test_root/stderr" >&2
		return 1
	fi
}

# A command no rule could approve starts no Git, and the denial checks and approvals share their Git lookups.
git_log="$test_root/git.log"
mkdir -p "$test_root/bin"
cat >"$test_root/bin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$git_log"
exec "$(command -v git)" "\$@"
EOF
chmod +x "$test_root/bin/git"
record_git() {
	: >"$git_log"
	PATH="$test_root/bin:$PATH" "$@"
}
record_git expect_silent permission_request 'ls -la'
[ ! -s "$git_log" ]
record_git expect_silent pre_tool_use 'git diff'
[ -s "$git_log" ]
[ -z "$(sort "$git_log" | uniq -d)" ]
for command in 'git push origin HEAD' 'git diff --stat' 'git diff -- a b'; do
	record_git expect_allowed "$command"
	[ -z "$(sort "$git_log" | uniq -d)" ]
done

for command in \
	'git push -u origin HEAD' \
	'git push --set-upstream origin HEAD' \
	'git branch --show-current' \
	'git fetch origin' \
	'git ls-remote origin' \
	'git status --short' \
	'git diff --check' \
	'git log --oneline -1' \
	'git show HEAD' \
	'git rev-parse HEAD' \
	'git ls-files' \
	'git --no-pager log --oneline -1' \
	'git --no-pager show HEAD' \
	'git --no-pager diff --stat' \
	'git switch feat/test' \
	'git switch -c feat/new' \
	'git add file' \
	'git add -- --force' \
	'git commit -c HEAD' \
	'git log -c -1' \
	'git commit --amend --no-edit' \
	'git merge feat/test' \
	'git rebase --continue' \
	'git cherry-pick --abort' \
	"git -C $tmpdir status" \
	"git log --format='a>b'" \
	'GIT_PAGER=cat git log --oneline -1'; do
	expect_allowed "$command"
done

# Commands outside the approved forms are left to Codex even in a trusted checkout.
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	'git pull --ff-only' \
	'git push' \
	'git push origin feat/test' \
	$'git push\norigin HEAD' \
	'git --paginate log' \
	'git diff -- /etc/hosts' \
	'git diff -- ../outside' \
	$'git status\ntouch /tmp/outside' \
	'git status `id`' \
	'git status > /tmp/outside' \
	'/tmp/git status'; do
	expect_silent permission_request "$command"
done

for variable in GIT_SSH_COMMAND GIT_DIR GIT_WORK_TREE; do
	if [ "$variable" = GIT_SSH_COMMAND ]; then
		value=false
	else
		value="$tmpdir/.git"
	fi
	expect_silent permission_request_with_env "$variable" "$value" 'git fetch origin'
done

git -C "$tmpdir" config diff.external 'touch /tmp/outside'
expect_denied 'git diff'
git -C "$tmpdir" config --unset-all diff.external
git -C "$tmpdir" config diff.x.textconv 'touch /tmp/outside'
expect_denied 'git log -p'
git -C "$tmpdir" config --unset-all diff.x.textconv
git -C "$tmpdir" config core.sshCommand 'touch /tmp/outside'
expect_denied 'git fetch origin'
git -C "$tmpdir" config --unset-all core.sshCommand

# Remote trust; dot-tools/git_trust covers the other untrusted remotes.
git -C "$tmpdir" remote set-url origin https://example.com/riii111/test.git
expect_silent permission_request 'git push origin HEAD'
expect_silent permission_request 'git fetch origin'

git -C "$tmpdir" remote set-url origin git@github.com:riii111/test.git
expect_allowed 'git push origin HEAD'

mkdir -p "$test_home/.ssh"
printf 'Host github.com\n  HostName ssh.github.com\n  Port 443\n' >"$test_home/.ssh/config"
expect_allowed 'git push origin HEAD'
rm -f "$test_home/.ssh/config"

git -C "$tmpdir" switch -q -c main
expect_silent permission_request 'git push origin HEAD'

# The owner and repository of a checkout match its remote in any case.
tmpdir="$test_home/ghq/github.com/Riii111/Upper"
mkdir -p "$tmpdir"
git -C "$tmpdir" init -q
git -C "$tmpdir" switch -q -c feat/test
git -C "$tmpdir" remote add origin git@github.com:riii111/upper.git
expect_allowed 'git status'
expect_allowed 'git push origin HEAD'
git -C "$tmpdir" remote set-url origin git@github.com:riii111/other.git
expect_silent permission_request 'git status'

printf 'codex permission hook tests passed\n'
