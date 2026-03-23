#!/bin/bash
# PR Review - Phase 0: Worktree準備
# Usage: pr-review-setup.sh <PR_NUMBER>
#
# 出力（stdout）:
#   WORKTREE_DIR=<path>
#   REVIEW_DIR=<path>
#   PR_BRANCH=<branch>
#   BASE_BRANCH=<branch>

set -euo pipefail

PR_NUMBER="${1:?Usage: pr-review-setup.sh <PR_NUMBER>}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_ROOT")"

# PRのブランチ名を取得
PR_BRANCH="$(gh pr view "$PR_NUMBER" --json headRefName --jq '.headRefName')"
BASE_BRANCH="$(gh pr view "$PR_NUMBER" --json baseRefName --jq '.baseRefName')"

WORKTREE_DIR="${REPO_ROOT}/../${REPO_NAME}-pr-${PR_NUMBER}"
REVIEW_DIR="${REPO_ROOT}/reviews/$(echo "$PR_BRANCH" | tr '/' '-')"

# Worktree作成（既存なら再利用）
if [ -d "$WORKTREE_DIR" ]; then
  echo "Worktree already exists: $WORKTREE_DIR" >&2
  # HEADを最新に更新
  git fetch origin "$PR_BRANCH"
  git -C "$WORKTREE_DIR" checkout "origin/${PR_BRANCH}" --detach 2>/dev/null || true
else
  git fetch origin "$PR_BRANCH"
  git worktree add "$WORKTREE_DIR" "origin/${PR_BRANCH}"
fi

# レビュー出力ディレクトリ作成
mkdir -p "$REVIEW_DIR"

# 結果を stdout に出力（呼び出し側がパースする）
echo "WORKTREE_DIR=${WORKTREE_DIR}"
echo "REVIEW_DIR=${REVIEW_DIR}"
echo "PR_BRANCH=${PR_BRANCH}"
echo "BASE_BRANCH=${BASE_BRANCH}"
