#!/bin/zsh
# Rust + SQL 統合 pre-commit hook (template)
# ---------------------------------------------
#  - Rust  : cargo fmt
#  - SQL   : sqlfluff fix (並列)
# -------------------------------------

set -euo pipefail

readonly staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"

# -------------------------------------
# Utility
# -------------------------------------
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
# Rust
# -------------------------------------
if echo "$staged_files" | grep -qE "\.rs$"; then
  echo "🦀 Rustファイルが検出されたのだ！"
  _format_and_notify "cargo fmt" "\\.rs$" "✅ Rust format successful" "❌ cargo fmt error"
fi

# -------------------------------------
# SQL
# -------------------------------------
if echo "$staged_files" | grep -qE "\.sql$"; then
  echo "🔍 SQLファイルが検出されたのだ！"

  if ! command -v sqlfluff &>/dev/null; then
    echo "⚠️ sqlfluffがインストールされていないのだ！ (pip install sqlfluff)"
  else
    sql_files=$(echo "$staged_files" | grep "\.sql$")
    num_cores=$(sysctl -n hw.ncpu)

    # 並列で sqlfluff fix
    echo "$sql_files" | xargs -n1 -P"$num_cores" -I{} sh -c 'sqlfluff fix "{}" --force'

    # xargs 内の失敗検知 (sqlfluff が非ゼロなら set -e で検知され exit)
    _format_and_notify "true" "\\.sql$" "✅ SQL format successful" "❌ sqlfluff fix error"
  fi
fi

exit 0 
