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
    echo "使い方: setup-git-hooks <テンプレート>"
    list-git-hook-templates
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
  local -a templates=("$GIT_HOOK_TEMPLATE_DIR"/*.(zsh|sh)(N-.:t))
  if (( ${#templates} )); then
    printf '  %s\n' "${templates[@]}"
  else
    echo "  テンプレートが見つからないのだ"
  fi
}

