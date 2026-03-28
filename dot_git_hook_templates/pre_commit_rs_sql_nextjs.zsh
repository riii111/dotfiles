#!/bin/zsh
# Rust + SQL + Next.js 統合 pre-commit hook (template)
# ---------------------------------------------
#  - Rust  : cargo fmt
#  - SQL   : sqlfluff fix
#  - FE    : yarn lint:fix (biome)
# ---------------------------------------------

set -euo pipefail

readonly staged_files="$(git diff --cached --name-only --diff-filter=ACMR)"
readonly repo_root="$(git rev-parse --show-toplevel)"

# -------------------------------------
# Utility
# -------------------------------------
_format_and_notify() {
  local cmd="$1" add_pattern="$2" ok_msg="$3" ng_msg="$4" workdir="$5"

  (cd "$workdir" && eval "$cmd")
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    if [[ -n "$add_pattern" ]]; then
      # shellcheck disable=SC2086
      git add $(echo "$staged_files" | grep -E "$add_pattern") || true
    fi
    echo "✅ ${ok_msg}"
  else
    echo "❌ ${ng_msg}"
    exit 1
  fi
}

# -------------------------------------
# Rust (backend)
# -------------------------------------
if echo "$staged_files" | grep -qE "\.rs$"; then
  echo "🦀 Rustファイルが検出されました！"
  _format_and_notify "cargo fmt" "\\.rs$" "✅ Rust format successful" "❌ cargo fmt error" "$repo_root/backend"
fi

# -------------------------------------
# SQL (root または backend 配下想定)
# -------------------------------------
if echo "$staged_files" | grep -qE "\.sql$"; then
  echo "🔍 SQLファイルが検出されました！"
  if command -v sqlfluff &>/dev/null; then
    sql_files=$(echo "$staged_files" | grep "\.sql$")
    num_cores=$(sysctl -n hw.ncpu)

    # 並列フォーマット
    echo "$sql_files" | xargs -n1 -P"$num_cores" -I{} sh -c 'sqlfluff fix "{}" --force'

    _format_and_notify "true" "\\.sql$" "✅ SQL format successful" "❌ sqlfluff fix error" "$repo_root"
  else
    echo "⚠️ sqlfluffがインストールされてません！ (pip install sqlfluff)"
  fi
fi

# -------------------------------------
# Frontend (frontend 配下)
# -------------------------------------
if echo "$staged_files" | grep -qE "frontend/.*\.(ts|tsx|js|jsx)$"; then
  echo "⚛️ フロントエンドファイルが検出されました！"
  _format_and_notify "yarn lint:fix" "frontend/.*\\.(ts|tsx|js|jsx)$" "✅ Frontend format successful" "❌ biome lint error" "$repo_root/frontend"
fi

exit 0 
