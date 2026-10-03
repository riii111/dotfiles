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
tmpdir="$test_home/ghq/github.com/riii111/test"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$tmpdir"
git -C "$tmpdir" init -q
git -C "$tmpdir" switch -q -c feat/test
git -C "$tmpdir" remote add origin https://github.com/riii111/test.git
main_repo="$test_home/ghq/github.com/riii111/main-repo"
mkdir -p "$main_repo"
git -C "$main_repo" init -q
git -C "$main_repo" switch -q -c main
git -C "$main_repo" remote add origin https://github.com/riii111/main-repo.git

pre_tool_use() {
	HOME="$test_home" jq -n --arg cwd "${hook_cwd:-$tmpdir}" --arg command "$1" \
		'{cwd:$cwd,hook_event_name:"PreToolUse",tool_input:{command:$command,description:"probe"}}' |
		HOME="$test_home" python3 "$runner" "$hook" "$test_home"
}

decision_is() {
	jq -e --arg decision "$1" '.hookSpecificOutput.permissionDecision == $decision' >/dev/null
}

for command in \
	'git status && git diff | head -5' \
	'git log --oneline 2>&1 | tail -2; git status -sb' \
	"cd $tmpdir && git fetch origin" \
	'gh pr checks 1 | tail -3' \
	'git push -u origin HEAD 2>&1 | tail -1' \
	'git status ;' \
	'git log -1 3>/dev/null' \
	'git log --oneline | grep push' \
	"git status && echo 'push complete'" \
	'git status | rg --no-config -c foo'; do
	output="$(pre_tool_use "$command")"
	decision_is allow <<<"$output"
	jq -e --arg command "$command" \
		'.hookSpecificOutput.updatedInput == {command:$command,description:"probe",dangerouslyDisableSandbox:true}' \
		<<<"$output" >/dev/null
done

for command in \
	'git reset --hard' \
	'rm -rf build' \
	'git status && git reset --hard HEAD~1' \
	'gh auth token' \
	'gh auth token | wc -c' \
	'git status && gcloud auth print-access-token'; do
	pre_tool_use "$command" | decision_is ask
done

# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	'echo done | wc -l' \
	'touch file' \
	'git status && touch outside' \
	'git push origin feat/test' \
	'git status; echo $(touch outside)'; do
	test -z "$(pre_tool_use "$command")"
done

output="$(pre_tool_use 'cd missing-dir && git status')"
test -z "$output"
pre_tool_use 'cd missing-dir && git push' | decision_is ask
output="$(pre_tool_use $'git status\v')"
test -z "$output"

# Inputs from the review of the first compound-command design; none may be approved.
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	'printf -v PATH /tmp/probe-bin; git status' \
	'git status && cat -- -secret' \
	'git status | uniq -- - -output=ignored' \
	'git status && cat *.txt' \
	"git status && cat 'secret 2>&1 notes'" \
	$'git status && jq -n -L . \'import "probe" as $s; $s::s\'' \
	'git status && grep -RS pattern inside-dir' \
	'git status | grep -R pattern'; do
	output="$(pre_tool_use "$command")"
	test -z "$output"
done
pre_tool_use 'git switch main && git push origin HEAD' | decision_is ask
for command in \
	"echo '&&' cd ../test; git push origin HEAD" \
	'cd ../test | git push origin HEAD' \
	'git status || cd ../test; git push origin HEAD'; do
	hook_cwd="$main_repo" pre_tool_use "$command" | decision_is ask
done
hook_cwd="$main_repo" pre_tool_use "cd $tmpdir && git push origin HEAD" | decision_is allow

# Inputs from the verification of the narrowed design.
evil="$test_root/evil"
mkdir -p "$evil"
git -C "$evil" init -q
git -C "$evil" switch -q -c main
ln -s "$tmpdir" "$evil/S"
for command in \
	'cd ./S/.. && git status' \
	'cd S && git status' \
	'cd ./S && git status'; do
	output="$(hook_cwd="$evil" pre_tool_use "$command")"
	test -z "$output"
done
hook_cwd="$evil/S" pre_tool_use 'cd .. && git push origin HEAD' | decision_is ask
output="$(hook_cwd="$evil/S" pre_tool_use 'cd ./. && git status')"
test -z "$output"
git -C "$tmpdir" config alias.pf 'push --force-with-lease'
git -C "$tmpdir" config alias.st status
# shellcheck disable=SC2016 # Literal expansions are hook inputs, not test-shell operations.
for command in \
	'GIT_PAGER=cat git switch main && git push origin HEAD' \
	'git rebase origin/main main && git push origin HEAD' \
	"git -P -C $main_repo push" \
	"git -c color.ui=never -C $main_repo push" \
	"git --git-dir=$main_repo/.git push" \
	"GIT_DIR=$main_repo/.git git push" \
	'git symbolic-ref HEAD refs/heads/main && git push origin HEAD' \
	'gh pr checkout 1 && git push origin HEAD' \
	"pushd $main_repo && git push" \
	'/usr/bin/git push origin main' \
	'command git push' \
	'env git push' \
	"sh -c 'git push'" \
	'echo | xargs git push' \
	"git 'push' origin HEAD; echo \$HOME" \
	$'git pu\\sh' \
	'git pf'; do
	pre_tool_use "$command" | decision_is ask
done
# Inputs from the second review of the narrowed design.
GIT_DIR="$main_repo/.git" pre_tool_use 'git push origin HEAD' | decision_is ask
detached="$test_home/ghq/github.com/riii111/detached"
mkdir -p "$detached"
git -C "$detached" init -q
git -C "$detached" -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init
git -C "$detached" switch -q --detach
git -C "$detached" remote add origin https://github.com/riii111/detached.git
hook_cwd="$detached" pre_tool_use 'git push origin HEAD:refs/heads/review-probe' | decision_is ask
for command in \
	'git st' \
	'git status | rg /tmp/outside.txt' \
	$'git status >\n/dev/null' \
	'git status | head -٢'; do
	output="$(pre_tool_use "$command")"
	test -z "$output"
done
HOME="$test_home" jq -n --arg cwd "$tmpdir" \
	'{cwd:$cwd,hook_event_name:"PreToolUse",tool_input:{command:"git -C a\u0000b status"}}' |
	HOME="$test_home" python3 "$runner" "$hook" "$test_home" | decision_is ask

git -C "$tmpdir" switch -q -c main
for command in \
	'git push' \
	'git push origin HEAD' \
	'git status && git push -u origin main' \
	"git -C $tmpdir push"; do
	pre_tool_use "$command" | decision_is ask
done

printf 'claude command hook tests passed\n'
