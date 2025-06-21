#!/bin/zsh
# Rust 専用 pre-commit hook (template)
# -------------------------------------
#  - Rust  : cargo fmt
# -------------------------------------

set -euo pipefail

readonly staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"

# -------------------------------------
# Utility
# -------------------------------------
_format_and_notify() {
  local cmd="$1" add_pattern="$2" ok_msg="$3" ng_msg="$4"

  if eval "$cmd"; then
    # フォーマットで変更が発生したファイルを再ステージ
    if [[ -n "$add_pattern" ]]; then
      # shellcheck disable=SC2086
      git add $(echo "$staged_files" | grep -E "$add_pattern") || true
    fi
    if command -v osascript &>/dev/null; then
      osascript -e "display notification \"${ok_msg}\" with title \"git pre-commit\""
    fi
    echo "✅ ${ok_msg}"
  else
    if command -v osascript &>/dev/null; then
      osascript -e "display notification \"${ng_msg}\" with title \"git pre-commit\" sound name \"Basso\""
    fi
    echo "❌ ${ng_msg}"
    exit 1
  fi
}

# -------------------------------------
# Rust
# -------------------------------------
if echo "$staged_files" | grep -qE "\.rs$"; then
  echo "🦀 Rustファイルが検出されたのだ！"
  _format_and_notify "cargo fmt" "\\.rs$" "✅ Rust format successful" "❌ cargo fmt error"
fi

exit 0 
