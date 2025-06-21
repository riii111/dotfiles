#!/usr/bin/env zsh

export GIT_HOOK_TEMPLATE_DIR="$HOME/.git_hook_templates"

function _ensure_hook_template_dir() {
  mkdir -p "$GIT_HOOK_TEMPLATE_DIR"
}

function _create_hook_from_template() {
  local template="$1" dest="$2"
  if [[ ! -f "$GIT_HOOK_TEMPLATE_DIR/$template" ]]; then
    echo "❌ テンプレート $template が見つからないのだ！ ($GIT_HOOK_TEMPLATE_DIR)"
    return 1
  fi
  ln -sf "$GIT_HOOK_TEMPLATE_DIR/$template" "$dest"
  chmod +x "$dest"
}

function setup-git-hooks() {
  local template="$1"
  if [[ -z "$template" ]]; then
    echo ""
    echo ""
    echo "利用可能なテンプレート:"
    echo "  pre_commit_rust.zsh        - Rust専用 (cargo fmt)"
    echo "  pre_commit_rust_sql.zsh    - Rust + SQL (cargo fmt + sqlfluff)"
    echo "  pre_commit_go.zsh          - Go専用 (goimports)"
    echo "  pre_commit_rs_next_sql.zsh - Rust + Next.js + SQL統合"
    return 1
  fi

  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$repo_root" ]]; then
    echo "❌ Gitリポジトリではないのだ！"
    return 1
  fi

  local hooks_dir="$repo_root/.git/hooks"
  local pre_commit_hook="$hooks_dir/pre-commit"

  _ensure_hook_template_dir
  _create_hook_from_template "$template" "$pre_commit_hook"

  echo "✅ Git フック設定が完了したのだ！ (テンプレート: $template)"
}

function list-git-hook-templates() {
  _ensure_hook_template_dir
  echo "利用可能なGitフックテンプレート:"
  if [[ -d "$GIT_HOOK_TEMPLATE_DIR" ]]; then
    ls -la "$GIT_HOOK_TEMPLATE_DIR" | grep -E '\.(zsh|sh)$' | awk '{print "  " $9}'
  else
    echo "  テンプレートディレクトリが存在しないのだ"
  fi
} 

