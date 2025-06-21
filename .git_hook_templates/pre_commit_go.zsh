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
    command -v osascript &>/dev/null && \
      osascript -e "display notification '✅ ${ok_msg}' with title '${ok_msg}'"
    echo "✅ ${ok_msg}"
  else
    command -v osascript &>/dev/null && \
      osascript -e "display notification '❌ ${ng_msg}' with title '${ng_msg}' sound name 'Basso'"
    echo "❌ ${ng_msg}"
    exit 1
  fi
}

if echo "$staged_files" | grep -qE "\.go$"; then
  echo "🐹 Goファイルが検出されたのだ！"

  # goimports を個別ファイルごとに実行
  go_files=$(echo "$staged_files" | grep "\.go$")
  for f in $go_files; do
    _format_and_notify "goimports -w \"$f\"" "Go format successful ($f)" "goimports error ($f)"
  done

  # フォーマット済みファイルを再ステージ
  # shellcheck disable=SC2086
  git add $go_files
fi

exit 0 
