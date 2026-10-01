#!/usr/bin/env bash
# Allow rules cannot see the current branch, so a push while on main or master asks first.

set -euo pipefail

input="$(cat)"
command="$(jq -r '.tool_input.command // ""' <<<"$input")"
cwd="$(jq -r '.cwd // ""' <<<"$input")"

[[ "$command" =~ (^|[[:space:];&|])git[[:space:]]+push([[:space:]]|$) ]] || exit 0

branch="$(git -C "${cwd:-.}" branch --show-current 2>/dev/null || true)"
case "$branch" in
main | master) ;;
*) exit 0 ;;
esac

jq -n --arg branch "$branch" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: "git push while on \($branch)"
  }
}'
