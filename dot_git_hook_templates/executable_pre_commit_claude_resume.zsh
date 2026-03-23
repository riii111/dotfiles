#!/bin/zsh
# Claude Resume プロジェクト専用 pre-commit hook
# ---------------------------------------------
#  - Rust  : cargo fmt (workspace root)
#  - UI    : biome format + check (ui/)
# ---------------------------------------------

set -euo pipefail

readonly staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"
readonly repo_root="$(git rev-parse --show-toplevel)"

_format_and_notify() {
  local cmd="$1" add_pattern="$2" ok_msg="$3" ng_msg="$4"

  if eval "$cmd"; then
    if [[ -n "$add_pattern" ]]; then
      # shellcheck disable=SC2086
      git add $(echo "$staged_files" | grep -E "$add_pattern") || true
    fi
    command -v osascript &>/dev/null && \
      osascript -e "display notification \"${ok_msg}\" with title \"git pre-commit\""
    echo "✅ ${ok_msg}"
  else
    command -v osascript &>/dev/null && \
      osascript -e "display notification \"${ng_msg}\" with title \"git pre-commit\" sound name \"Basso\""
    echo "❌ ${ng_msg}"
    exit 1
  fi
}

# -------------------------------------
# Rust (workspace root)
# -------------------------------------
if echo "$staged_files" | grep -qE "\.rs$"; then
  echo "🦀 Rustファイルが検出されたのだ！"
  cd "$repo_root" && _format_and_notify "cargo fmt" "\\.rs$" "✅ Rust format successful" "❌ cargo fmt error"
fi

# -------------------------------------
# UI (ui/ ディレクトリ配下)
# -------------------------------------
if echo "$staged_files" | grep -qE "ui/.*\.(ts|tsx|js|jsx)$"; then
  echo "⚛️ UIファイルが検出されたのだ！"
  cd "$repo_root/ui" && _format_and_notify "npm run format && npm run lint" "ui/.*\\.(ts|tsx|js|jsx)$" "✅ UI format and lint successful" "❌ biome format/lint error"
fi

exit 0