#!/usr/bin/env bash

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
	printf 'codex rules tests skipped: codex not installed\n'
	exit 0
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
rules="$repo_root/dot_codex/rules/default.rules"

decision() {
	codex execpolicy check --rules "$rules" -- "$@" | jq -r '.decision // "no_match"'
}

test "$(decision cargo metadata --no-deps)" = no_match
test "$(decision git status)" = no_match
test "$(decision rg pattern)" = prompt
test "$(decision jq . file.json)" = no_match
test "$(decision mkdir build)" = no_match
test "$(decision git branch --show-current)" = prompt
test "$(decision git remote -v)" = no_match
test "$(decision gh pr view 26)" = allow
test "$(decision gh search auth token)" = allow
test "$(decision gcloud run jobs list)" = allow
test "$(decision gh-pr-comments 26 --compact)" = allow
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
test "$(decision git clean -fdx)" = forbidden
test "$(decision git gc --prune=now)" = forbidden
test "$(decision git push --mirror origin)" = forbidden
test "$(decision git push -d origin old)" = forbidden
test "$(decision git push --prune origin)" = forbidden
test "$(decision gh repo delete owner/repo)" = forbidden
test "$(decision gcloud projects delete project)" = forbidden
test "$(decision git restore .)" = forbidden
test "$(decision git restore :/)" = forbidden
test "$(decision find . -delete)" = forbidden
test "$(decision git worktree remove ../worktree)" = prompt
test "$(decision git submodule update --init)" = prompt
test "$(decision gh pr review 26 --approve)" = prompt
test "$(decision gh workflow run ci.yml)" = prompt

printf 'codex rules tests passed\n'
