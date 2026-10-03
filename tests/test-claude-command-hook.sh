#!/usr/bin/env bash

set -euo pipefail

while IFS= read -r variable; do
	unset "$variable"
done < <(env | sed -n 's/=.*//p' | sed -n '/^GIT_/p')
export GIT_PAGER=cat
export GIT_OPTIONAL_LOCKS=0
export GIT_EDITOR=true

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$repo_root/dot_local/share/agent-policy/executable_claude_pre_tool_use.py"
runner="$repo_root/tests/run-codex-python-with-home.py"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/claude-command-hook-test.XXXXXX")"
# The policy only follows `cd` when the logical path is the physical one.
test_root="$(cd "$test_root" && pwd -P)"
test_home="$test_root/home"
trap 'rm -rf "$test_root"' EXIT

make_repo() {
	local path="$test_home/ghq/github.com/riii111/$1"
	mkdir -p "$path"
	git -C "$path" init -q
	git -C "$path" switch -q -c "$2"
	git -C "$path" remote add origin "https://github.com/riii111/$1.git"
	printf '%s\n' "$path"
}
feature="$(make_repo feature feat/test)"
main_repo="$(make_repo main-repo main)"
detached="$(make_repo detached main)"
git -C "$detached" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
git -C "$detached" switch -q --detach

pre_tool_use() {
	HOME="$test_home" jq -n --arg cwd "${hook_cwd:-$feature}" --arg command "$1" \
		'{cwd:$cwd,hook_event_name:"PreToolUse",tool_input:{command:$command}}' |
		HOME="$test_home" python3 "$runner" "$hook" "$test_home"
}

asks() {
	pre_tool_use "$1" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null
}

stays_silent() {
	local output
	output="$(pre_tool_use "$1")"
	test -z "$output"
}

# The hook only ever asks; everything else is left to the sandbox and the rules.
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	'git status && git diff | head -5' \
	'git log --oneline 2>&1 | tail -2; git status -sb' \
	"cd $feature && git fetch origin" \
	'git push origin HEAD' \
	'git push -u origin feat/test 2>&1 | tail -1' \
	'git add file && git commit -m message && git push -u origin HEAD' \
	'git log --oneline | grep push' \
	"git status && echo 'push complete'" \
	'git status; echo $(touch outside)' \
	'touch file' \
	'cd missing-dir && git status' \
	'git --version' \
	'git apply x.patch' \
	'git lfs ls-files' \
	$'git status\v'; do
	stays_silent "$command"
done

# Commands the shared policy forbids on their own, alone or inside a compound.
for command in \
	'git reset --hard' \
	'rm -rf build' \
	'git status && git reset --hard HEAD~1' \
	'gh auth token' \
	'gh auth token | wc -c' \
	'git status && gcloud auth print-access-token'; do
	asks "$command"
done

# Pushes whose branch, repository or options cannot be confirmed.
git -C "$feature" config alias.pf 'push --force-with-lease'
git -C "$feature" config alias.st status
git -C "$feature" config alias.p2 publish
git -C "$feature" config alias.publish push
git -C "$feature" config alias.loop1 loop2
git -C "$feature" config alias.loop2 loop1
stays_silent 'git st'
stays_silent 'gh pr view 1 && git log | grep push && git push origin HEAD'
evil="$test_root/evil"
mkdir -p "$evil"
git -C "$evil" init -q
git -C "$evil" switch -q -c main
ln -s "$feature" "$evil/S"
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	'git switch main && git push origin HEAD' \
	'GIT_PAGER=cat git switch main && git push origin HEAD' \
	'git rebase origin/main main && git push origin HEAD' \
	'git symbolic-ref HEAD refs/heads/main && git push origin HEAD' \
	'gh pr checkout 1 && git push origin HEAD' \
	'PATH=/tmp/probe-bin grep foo && git push origin HEAD' \
	"'GIT_PAGER=cat' git status && git push origin HEAD" \
	"git -P -C $main_repo push" \
	"git -c color.ui=never -C $main_repo push" \
	"git --git-dir=$main_repo/.git push" \
	"GIT_DIR=$main_repo/.git git push" \
	"pushd $main_repo && git push" \
	'/usr/bin/git push origin main' \
	'command git push' \
	'env git push' \
	"sh -c 'git push'" \
	'echo | xargs git push' \
	"git 'push' origin HEAD; echo \$HOME" \
	$'git pu\\sh' \
	'git pf' \
	'git p2 origin HEAD' \
	'git loop1' \
	'git lfs push origin main' \
	'sort -o .git/HEAD branch.txt && git push origin HEAD' \
	'uniq branch.txt .git/HEAD && git push origin HEAD' \
	'rg --pre ./switch x && git push origin HEAD' \
	'cd missing-dir && git push'; do
	asks "$command"
done
GIT_DIR="$main_repo/.git" asks 'git push origin HEAD'
hook_cwd="$detached" asks 'git push origin HEAD:refs/heads/review-probe'
for command in \
	"echo '&&' cd ../feature; git push origin HEAD" \
	'cd ../feature | git push origin HEAD' \
	'git status || cd ../feature; git push origin HEAD' \
	'cd ../feature && git push origin HEAD'; do
	hook_cwd="$main_repo" asks "$command"
done
hook_cwd="$main_repo" stays_silent "cd $feature && git push origin HEAD"
hook_cwd="$evil/S" asks 'cd .. && git push origin HEAD'
for command in \
	'git push' \
	'git push origin HEAD' \
	'git status && git push -u origin main'; do
	hook_cwd="$main_repo" asks "$command"
done

HOME="$test_home" jq -n --arg cwd "$feature" \
	'{cwd:$cwd,hook_event_name:"PreToolUse",tool_input:{command:"git -C a\u0000b status"}}' |
	HOME="$test_home" python3 "$runner" "$hook" "$test_home" |
	jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null

printf 'claude command hook tests passed\n'
