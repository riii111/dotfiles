#!/usr/bin/env bash

set -euo pipefail

while IFS= read -r variable; do
	unset "$variable"
done < <(env | sed -n 's/=.*//p' | sed -n '/^GIT_/p')
export GIT_PAGER=cat

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/dot_codex/hooks/executable_permission_request.py"
runner="$repo_root/tests/run-codex-python-with-home.py"
hooks_config="$repo_root/dot_codex/hooks.json"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/codex-permission-hook-test.XXXXXX")"
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
		HOME="$test_home" python3 "$runner" "$hook" "$test_home"
}

jq -e '.hooks.PreToolUse[0].matcher == "^Bash$"' "$hooks_config" >/dev/null
jq -e '.hooks.PermissionRequest[0].matcher == "^Bash$"' "$hooks_config" >/dev/null

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

permission_request 'git push -u origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git push origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git push --set-upstream origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'gh auth status' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git branch --show-current' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git fetch origin' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'git ls-remote origin' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
for command in \
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
	'git commit -c HEAD' \
	'git log -c -1' \
	'git commit --amend --no-edit' \
	'git merge feat/test' \
	'git rebase --continue' \
	'git cherry-pick --abort'; do
	permission_request "$command" | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
done
permission_request "git -C $tmpdir status" | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
test -z "$(permission_request 'git pull --ff-only')"
permission_request 'git fetch --force origin' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'git fetch origin +main:main' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'git fetch --update-head-ok origin' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'gh auth status --show-token' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'gh auth status --hostname github.com --show-token' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'gh auth status --hostname github.com -t' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
permission_request 'git reset HEAD~1 --hard' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
test -z "$(permission_request 'gh auth status --hostname github.com')"
test -z "$(permission_request 'git push')"
test -z "$(permission_request 'git push origin feat/test')"
for command in \
	$'git push\norigin HEAD' \
	$'gh auth\nstatus' \
	$'gh\nauth status'; do
	test -z "$(permission_request "$command")"
done

for command in \
	'git reset HEAD~1 --hard' \
	'FOO=1 git reset --hard' \
	'git restore .' \
	'git restore :/' \
	'git restore --staged --worktree .' \
	'git switch -f old' \
	'git switch -C old' \
	'git switch --force-create old' \
	'git switch --discard-changes old' \
	'git branch -D old' \
	'git branch --delete --force old' \
	'git branch --delete -f old' \
	'git fetch -f origin' \
	'git rebase --exec "touch outside" main' \
	'git switch --orphan empty' \
	'git diff --output=/tmp/codex-leak main' \
	'git diff --no-index /etc/hosts /etc/passwd' \
	'GIT_SEQUENCE_EDITOR="touch outside" git rebase -i main' \
	'GIT_SSH_COMMAND="touch outside" git fetch origin' \
	'GIT_EDITOR="touch outside" git commit' \
	'git fetch --force origin' \
	'git fetch origin +main:main' \
	'git fetch --update-head-ok origin' \
	'git add --for ignored' \
	'git switch --disc old' \
	'git switch --force-c old' \
	'git switch --or empty' \
	'git rebase --ex "touch outside" main' \
	'git reset --har HEAD' \
	'git push --mir origin' \
	'git push --del origin old' \
	'git push --pru origin' \
	'git clean --for -d' \
	'git checkout -- .' \
	'git stash clear' \
	'git stash drop' \
	'git add -f ignored' \
	'git clean -fdx' \
	'git gc --prune=now' \
	"git -c alias.x='!git push --force origin HEAD' x" \
	"git -c core.sshCommand='touch /tmp/outside' fetch origin" \
	'git --config-env=alias.x=GIT_ALIAS x' \
	'git -C repo push origin +main:main' \
	'git push origin :old' \
	'git push -d origin old' \
	'git push --prune origin' \
	'gh auth token' \
	'gh auth status --hostname github.com --show-token' \
	'gh repo delete owner/repo' \
	'gh ssh-key add key.pub' \
	'gh gpg-key add key.asc' \
	'gh auth login' \
	'gh auth refresh' \
	'gh auth setup-git' \
	'gcloud auth print-access-token' \
	'gcloud projects delete project' \
	'gcloud storage rm gs://bucket/object' \
	'gcloud run jobs delete job' \
	'gcloud run services delete service' \
	'gcloud iam service-accounts keys create key.json' \
	'terraform apply' \
	'terraform state rm resource.name' \
	'terraform state mv old new' \
	'terraform taint resource.name' \
	'terraform import resource.name id' \
	'terraform force-unlock lock-id' \
	'terraform workspace delete old' \
	'chezmoi purge' \
	'chezmoi destroy' \
	'bq rm dataset' \
	'sudo command' \
	'chmod 777 file' \
	'find . -delete'; do
	pre_tool_use "$command" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
done

for command in \
	'git add --for ignored' \
	'git switch --disc old' \
	'git switch --force-c old' \
	'git switch --or empty' \
	'git rebase --ex "touch outside" main'; do
	permission_request "$command" | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
done
for command in \
	'git reset --har HEAD' \
	'git push --mir origin' \
	'git push --del origin old' \
	'git push --pru origin' \
	'git clean --for -d'; do
	permission_request "$command" | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
done
permission_request 'git add -- --force' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
test -z "$(pre_tool_use 'git add -- --force')"
test -z "$(permission_request 'git --paginate log')"
permission_request 'git -c core.pager=cat log' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
pre_tool_use 'git -c core.pager=cat log' | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
# PreToolUse cannot request approval, so prompt-class operations remain governed by the sandbox.
test -z "$(pre_tool_use 'rm file')"
pre_tool_use '/usr/bin/git reset --hard' | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
pre_tool_use '/bin/rm -rf build' | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null

# Indirection and compound shell syntax must not bypass the deny checks.
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
	'nohup git reset --hard' \
	"printf 'git reset --hard\\n' | sh"; do
	pre_tool_use "$command" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
done

# Normal shell composition must not interrupt autonomous development work.
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in 'echo "$HOME"' 'git diff "$(git merge-base main HEAD)"' 'rg foo src/*.rs' 'source .venv/bin/activate'; do
	test -z "$(pre_tool_use "$command")"
done
test -z "$(pre_tool_use 'git diff --no-ext-diff --no-textconv')"
test -z "$(pre_tool_use 'rg textconv src')"
test -z "$(permission_request 'git diff -- /etc/hosts')"
test -z "$(permission_request 'git diff -- ../outside')"
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	$'git status\ntouch /tmp/outside' \
	'git status `id`' \
	'git status > /tmp/outside' \
	'/tmp/git status'; do
	test -z "$(permission_request "$command")"
done
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	'PATH=/tmp:$PATH git status' \
	"GIT_PAGER='touch /tmp/outside' git log" \
	"PAGER='touch /tmp/outside' git log"; do
	permission_request "$command" | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
done
permission_request "git log --format='a>b'" | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
permission_request 'GIT_PAGER=cat git log --oneline -1' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
test -z "$(pre_tool_use 'GIT_PAGER=cat git status')"

for variable in GIT_SSH_COMMAND GIT_DIR GIT_WORK_TREE; do
	if [ "$variable" = GIT_SSH_COMMAND ]; then
		value=false
	else
		value="$tmpdir/.git"
	fi
	test -z "$(permission_request_with_env "$variable" "$value" 'git fetch origin')"
done

git -C "$tmpdir" config diff.external 'touch /tmp/outside'
permission_request 'git diff' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
pre_tool_use 'git diff' | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
git -C "$tmpdir" config --unset-all diff.external
git -C "$tmpdir" config core.sshCommand 'touch /tmp/outside'
permission_request 'git fetch origin' | jq -e '.hookSpecificOutput.decision.behavior == "deny"' >/dev/null
pre_tool_use 'git fetch origin' | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null
git -C "$tmpdir" config --unset-all core.sshCommand
test -z "$(pre_tool_use 'git restore --staged .')"
test -z "$(pre_tool_use 'gh search code "auth token"')"
test -z "$(pre_tool_use 'git stash pop')"
test -z "$(pre_tool_use 'terraform state list')"

git -C "$tmpdir" remote set-url origin https://example.com/riii111/test.git
test -z "$(permission_request 'git push origin HEAD')"
test -z "$(permission_request 'git fetch origin')"
test -z "$(permission_request 'git ls-remote origin')"

git -C "$tmpdir" remote set-url origin git@github.com:riii111/test.git
permission_request 'git push origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null

mkdir -p "$test_home/.ssh"
printf 'Host github.com\n  HostName ssh.github.com\n  Port 443\n' >"$test_home/.ssh/config"
permission_request 'git push origin HEAD' | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null
rm -f "$test_home/.ssh/config"

mkdir -p "$test_home/.ssh"
printf 'Host work-github\n  HostName github.com\n' >"$test_home/.ssh/config"
git -C "$tmpdir" remote set-url origin https://work-github/riii111/test.git
test -z "$(permission_request 'git fetch origin')"
git -C "$tmpdir" remote set-url origin git@github.com:riii111/test.git

git -C "$tmpdir" remote set-url origin https://github.com/riii111/test.git
git -C "$tmpdir" config url."https://attacker.example/other.git".insteadOf https://github.com/riii111/test.git
test -z "$(permission_request 'git fetch origin')"
test -z "$(permission_request 'git push origin HEAD')"
git -C "$tmpdir" config --unset-all url."https://attacker.example/other.git".insteadOf
git -C "$tmpdir" remote set-url origin git@github.com:riii111/test.git

git -C "$tmpdir" remote set-url origin https://github.com/attacker/other.git
test -z "$(permission_request 'git push origin HEAD')"
test -z "$(permission_request 'git fetch origin')"
test -z "$(permission_request 'git ls-remote origin')"
git -C "$tmpdir" remote set-url origin git@github.com:riii111/test.git

git -C "$tmpdir" remote set-url --push origin https://github.com/attacker/other.git
test -z "$(permission_request 'git push origin HEAD')"
git -C "$tmpdir" remote set-url --delete --push origin https://github.com/attacker/other.git

git -C "$tmpdir" remote set-url --add --push origin https://github.com/riii111/test.git
git -C "$tmpdir" remote set-url --add --push origin https://example.com/riii111/test.git
test -z "$(permission_request 'git push origin HEAD')"

git -C "$tmpdir" switch -q -c main
test -z "$(permission_request 'git push origin HEAD')"

printf 'codex permission hook tests passed\n'
