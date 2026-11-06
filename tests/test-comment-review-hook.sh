#!/usr/bin/env bash

set -euo pipefail

while IFS= read -r variable; do
	unset "$variable"
done < <(env | sed -n 's/=.*//p' | sed -n '/^GIT_/p')
export GIT_PAGER=cat GIT_CONFIG_NOSYSTEM=1

# Tests the agent-hooks on PATH; the Nix dev shells build it from this checkout.
hook="${AGENT_HOOKS:-agent-hooks}"
tmp_base="${TMPDIR:-/tmp}"
test_root="$(mktemp -d "${tmp_base%/}/comment-review-hook-test.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
export HOME="$test_root/home"
repo="$test_root/repo"
mkdir -p "$HOME" "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
printf 'x = 1\n' >"$repo/a.py"
git -C "$repo" add a.py
git -C "$repo" commit -qm init
log="$HOME/.local/state/claude/comment-review-events.jsonl"

review() {
	jq -n --arg cwd "$repo" --arg command "$1" \
		'{cwd:$cwd,session_id:"s1",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$command}}' |
		"$hook" comment-review-check
}

expect_silent() {
	local output
	output="$(review "$1")"
	if [ -n "$output" ]; then
		printf 'expected no decision for %s, got: %s\n' "$1" "$output" >&2
		return 1
	fi
}

expect_denied() {
	local output
	output="$(review "$1")"
	if ! jq -e --arg expected "$2" '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains($expected))' <<<"$output" >/dev/null; then
		printf 'expected a denial with %s for %s, got: %s\n' "$2" "$1" "$output" >&2
		return 1
	fi
}

printf 'y = 2\n' >>"$repo/a.py"
git -C "$repo" add a.py
expect_silent 'git commit -m "feat: y"'
git -C "$repo" commit -qm y

printf '# TODO\nz = 3\n' >>"$repo/a.py"
git -C "$repo" add a.py
expect_denied 'git commit -m "feat: z"' 'a.py:3 [着手条件のないTODO] TODO'
expect_silent 'git commit -m "feat: z"'
jq -se 'map(.outcome) == ["blocked", "passed"] and .[0].rules == {"bare-todo": 1} and .[0].session == "s1"' "$log" >/dev/null
[ "$(stat -c %a "$log" 2>/dev/null || stat -f %Lp "$log")" = 600 ]
git -C "$repo" commit -qm z

# A comment that is not staged yet goes in with `-a` or a `git add` in the same command.
printf '# ---------\n' >>"$repo/a.py"
expect_silent 'git commit -m "feat: divider"'
expect_denied 'git commit -am "feat: divider"' '区切り線の見出し'
expect_silent 'git add -A && git commit -m "feat: divider"'

git -C "$repo" commit -qam divider

# A comment that no rule flags is still listed once for review.
printf '# Returns the total.\nw = 4\n' >>"$repo/a.py"
git -C "$repo" add a.py
expect_denied 'git commit -m "feat: w"' 'a.py:6 Returns the total.'
expect_silent 'git commit -m "feat: w"'

expect_silent 'git status'
