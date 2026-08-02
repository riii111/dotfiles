#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
rules="$repo_root/dot_codex/rules/default.rules"

decision() {
	codex execpolicy check --rules "$rules" -- "$@" | jq -r '.decision'
}

test "$(decision cargo metadata --no-deps)" = allow
test "$(decision cargo metadata)" != allow
test "$(decision git branch --show-current)" = prompt
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
test "$(decision rg --pre rm pattern)" = prompt
test "$(decision bat --pager rm file)" = prompt
test "$(decision git diff --ext-diff)" = prompt
test "$(decision git show --ext-diff HEAD)" = prompt
test "$(decision git log --ext-diff -p)" = prompt
test "$(decision git cat-file --filters HEAD:file)" = prompt
test "$(decision git branch -r -d origin/old)" = prompt
test "$(decision git switch --discard-changes old)" = prompt
test "$(decision git switch -C old)" = prompt
test "$(decision gh pr checkout 1 --force)" = prompt
test "$(decision tee .git/config)" = prompt
test "$(decision cp source .git/config)" = prompt
test "$(decision mv source .git/config)" = prompt
test "$(decision terraform output -raw secret)" = prompt
test "$(decision terraform show)" = prompt
test "$(decision printenv)" = prompt
test "$(decision ps e)" = prompt
test "$(decision git fetch --force origin)" = prompt
test "$(decision git fetch origin +main:main)" = prompt
test "$(decision git fetch --update-head-ok origin)" = prompt

printf 'codex rules tests passed\n'
