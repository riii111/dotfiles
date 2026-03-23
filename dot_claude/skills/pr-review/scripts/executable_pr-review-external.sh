#!/bin/bash
# PR Review - Phase 2: 外部ツールスキャン
# Usage: pr-review-external.sh <WORKTREE_DIR> <BASE_BRANCH>
#
# Codex CLI と CodeRabbit CLI を worktree 内で並列実行し、結果を stdout に出力する。
# ツールが未インストールの場合はスキップする。
#
# 出力（stdout）:
#   === CODEX_RESULT ===
#   (Codex の出力)
#   === CR_RESULT ===
#   (CodeRabbit の出力)

set -euo pipefail

WORKTREE_DIR="${1:?Usage: pr-review-external.sh <WORKTREE_DIR> <BASE_BRANCH>}"
BASE_BRANCH="${2:?Usage: pr-review-external.sh <WORKTREE_DIR> <BASE_BRANCH>}"

# worktree の存在確認
if [ ! -d "$WORKTREE_DIR" ]; then
  echo "ERROR: Worktree not found: $WORKTREE_DIR" >&2
  exit 1
fi

CODEX_TMP=$(mktemp)
CR_TMP=$(mktemp)
trap 'rm -f "$CODEX_TMP" "$CR_TMP"' EXIT

# Codex（利用可能な場合）— バックグラウンドで起動
CODEX_PID=""
if command -v codex &>/dev/null; then
  (cd "$WORKTREE_DIR" && RUST_LOG=off codex exec --sandbox read-only 2>/dev/null - <<CODEX_PROMPT > "$CODEX_TMP"
You are a PR reviewer. Review the changes on this branch compared to the base branch.

Instructions:
1. Run \`git diff origin/${BASE_BRANCH}..HEAD\` to see the changes
2. Read the modified files for full context
3. Identify issues: bugs, security risks, performance problems, design concerns
4. For each issue, include the file path and line number

Output format per finding:
### [severity]. [title]
\`file:L<line>\`
Description of the issue and why it matters.

Severity levels: Critical / Suggestion / Nit
CODEX_PROMPT
  ) &
  CODEX_PID=$!
else
  echo "codex CLI not found, skipping" >&2
fi

# CodeRabbit（利用可能な場合）— バックグラウンドで起動
CR_PID=""
if command -v cr &>/dev/null; then
  (cd "$WORKTREE_DIR" && cr --prompt-only -t committed --base "$BASE_BRANCH" 2>/dev/null > "$CR_TMP") &
  CR_PID=$!
else
  echo "cr CLI not found, skipping" >&2
fi

# 完了を待つ
[ -n "$CODEX_PID" ] && wait "$CODEX_PID" || true
[ -n "$CR_PID" ] && wait "$CR_PID" || true

# 結果を stdout に出力
echo "=== CODEX_RESULT ==="
cat "$CODEX_TMP"
echo ""
echo "=== CR_RESULT ==="
cat "$CR_TMP"
