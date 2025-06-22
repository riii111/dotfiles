#!/bin/zsh
# Go 専用 pre-commit hook (template)
# -------------------------------------
#  - Go    : goimports
# -------------------------------------

set -euo pipefail

readonly staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"

_format_and_notify() {
  local cmd="$1" ok_msg="$2" ng_msg="$3"
  if eval "$cmd"; then
    if command -v osascript &>/dev/null; then
      osascript -e "display notification \"${ok_msg}\" with title \"git pre-commit\""
    fi
    echo "${ok_msg}"
  else
    if command -v osascript &>/dev/null; then
      osascript -e "display notification \"${ng_msg}\" with title \"git pre-commit\" sound name \"Basso\""
    fi
    echo "${ng_msg}"
    exit 1
  fi
}

if echo "$staged_files" | grep -qE "\.go$"; then
  echo "🐹 Goファイルが検出されました！"

  # Goモジュールのルートディレクトリを見つける
  go_mod_dir=""
  if [[ -f "application/new/go.mod" ]]; then
    go_mod_dir="application/new"
  elif [[ -f "go.mod" ]]; then
    go_mod_dir="."
  fi

  if [[ -n "$go_mod_dir" ]]; then
    echo "🔧 Running golangci-lint --fix from $go_mod_dir"
    _format_and_notify "cd \"$go_mod_dir\" && golangci-lint run --fix >/dev/null" "✅ Go format successful" "❌ golangci-lint error"

    # フォーマット済みファイルを再ステージ
    go_files=$(echo "$staged_files" | grep "\.go$")
    for file in $go_files; do
      git add "$file" 2>/dev/null || true
    done
  else
    echo "⚠️ go.modが見つかりません！"
  fi
fi

exit 0 
