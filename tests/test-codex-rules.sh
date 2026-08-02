#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
rules="$repo_root/dot_codex/rules/default.rules"

decision() {
	codex execpolicy check --rules "$rules" -- "$@" | jq -r '.decision'
}

test "$(decision cargo metadata --no-deps)" = allow
test "$(decision cargo metadata)" != allow
test "$(decision git branch --show-current)" = allow
test "$(decision git remote -v)" = allow
test "$(decision env rm -rf target)" = prompt
test "$(decision fd -x rm '{}')" = prompt
test "$(decision awk 'BEGIN { system("rm file") }')" = prompt
test "$(decision xargs rm)" = prompt
test "$(decision git remote set-url origin https://example.com/repo.git)" = prompt
test "$(decision git branch -D old)" = prompt
test "$(decision git tag -d old)" = prompt
test "$(decision git stash clear)" = prompt
test "$(decision sed -i '' file)" = prompt
test "$(decision gh auth status --show-token)" = forbidden
test "$(decision gh auth status --hostname github.com --show-token)" = prompt
test "$(decision git reset HEAD --hard)" = forbidden
test "$(decision git reset HEAD~1 --hard)" = prompt
test "$(decision git cat-file -t HEAD)" = allow
test "$(decision git diff-tree HEAD)" = allow

printf 'codex rules tests passed\n'
