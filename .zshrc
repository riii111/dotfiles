# ==========================================
# XDG Base Directory
# ==========================================
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# ==========================================
# Zsh Startup Caching Mechanism
# ==========================================
# Cache slow initialization commands to improve startup speed
ZSHRC_CACHE_DIR="$XDG_CACHE_HOME/zsh"
ZSHRC_CACHE_FILE="$ZSHRC_CACHE_DIR/init-cache.zsh"
ZSHRC_SOURCE="$HOME/.zshrc"

[[ ! -d "$ZSHRC_CACHE_DIR" ]] && mkdir -p "$ZSHRC_CACHE_DIR"

if [[ ! -f "$ZSHRC_CACHE_FILE" ]] || [[ "$ZSHRC_SOURCE" -nt "$ZSHRC_CACHE_FILE" ]]; then
    {
        echo "# Generated at $(date)"
        echo "# This file is auto-generated. Do not edit manually."
        echo

        if command -v pyenv >/dev/null 2>&1; then
            echo "# pyenv initialization"
            pyenv init --path
        fi

        # brew --prefix llvm is slow
        if command -v brew >/dev/null 2>&1; then
            echo
            echo "# brew llvm path"
            echo "export PATH=\"$(brew --prefix llvm)/bin:\$PATH\""
        fi

        if command -v go >/dev/null 2>&1; then
            echo
            echo "# go paths"
            echo "export PATH=\"\$PATH:$(go env GOPATH)/bin:\$HOME/go/bin\""
        fi

    } > "$ZSHRC_CACHE_FILE"
fi

source "$ZSHRC_CACHE_FILE"

# ==========================================
# Shell Options
# ==========================================
setopt IGNORE_EOF

# History
HISTSIZE=10000
SAVEHIST=10000
setopt EXTENDED_HISTORY
setopt INC_APPEND_HISTORY
setopt HIST_IGNORE_SPACE
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

# ==========================================
# Prompt
# ==========================================
export PS1="%1~ %# "

# ==========================================
# Environment Variables
# ==========================================
# Editors
export EDITOR=nvim
export GIT_EDITOR=nvim
export VISUAL=nvim
export MANPAGER='nvim +Man!'

# ==========================================
# PATH Configuration
# ==========================================
typeset -U path PATH

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$PATH
export PATH="$HOME/bin:$PATH"

# Google Cloud SDK (lazy loading)
export CLOUDSDK_PYTHON=/opt/homebrew/bin/python3
export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"

# Load completions on first invocation
function gcloud() {
  unfunction gcloud gsutil bq 2>/dev/null
  source "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc"
  source "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"
  gcloud "$@"
}
function gsutil() {
  unfunction gcloud gsutil bq 2>/dev/null
  source "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc"
  source "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"
  gsutil "$@"
}
function bq() {
  unfunction gcloud gsutil bq 2>/dev/null
  source "/opt/homebrew/share/google-cloud-sdk/path.zsh.inc"
  source "/opt/homebrew/share/google-cloud-sdk/completion.zsh.inc"
  bq "$@"
}

# golang
export GOTOOLCHAIN=auto

# rust
export PATH="$HOME/.cargo/bin:$PATH"

export PNPM_HOME="$HOME/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# Git hooks
if [[ -f "$HOME/.git-hooks.zsh" ]]; then
  source "$HOME/.git-hooks.zsh"
fi

# Rust Development
function rust-test-unit() {
  local dir="${1:-$PWD}"
  (cd -- "$dir" && cargo nextest run --workspace --lib -j"$(sysctl -n hw.ncpu)" --features test_utils)
}

function rust-test-integration() {
  local dir="${1:-$PWD}"
  (cd -- "$dir" && cargo nextest run --workspace --test -j"$(sysctl -n hw.ncpu)" --features test_utils)
}

function rust-test-all() {
  local dir="${1:-$PWD}"
  (cd -- "$dir" && cargo nextest run --workspace -j"$(sysctl -n hw.ncpu)" --features test_utils)
}

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"

# ==========================================
# Interactive Shell Only
# ==========================================
[[ -o interactive ]] || return

# ==========================================
# Completion
# ==========================================
if [[ -o zle ]]; then
  # Homebrew completions
  FPATH="/opt/homebrew/share/zsh/site-functions:$FPATH"
  fpath+=~/.zfunc
  autoload -Uz compinit

  _deferred_compinit() {
    unfunction _deferred_compinit
    compinit  # no -C: cache benefit is minimal with few completions
    [[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
  }
  zmodload zsh/sched
  sched +0 _deferred_compinit

  # Completion styles
  zstyle ':completion:*' menu select
  zstyle ':completion:*' verbose yes
  zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
  zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'

  # zsh-autosuggestions
  [[ -f /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
    source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# ==========================================
# Modern CLI Tools Aliases
# ==========================================
# Use modern replacements for traditional Unix tools
alias cat='bat'
alias ls='eza'
alias ll='eza -hl'
alias la='eza -hla'
alias lt='eza --tree'
alias llg='eza -hlFg'

# ==========================================
# Basic Aliases
# ==========================================
alias vim='nvim'
alias v='nvim'
alias nv='nvim'
alias clr='clear'
alias o='open'
export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml"
alias lg='lazygit'

alias mkdir='mkdir -p'
alias mkd='mkdir -p'

alias dc='docker compose'
alias dcb='docker compose build'
alias dcbn='docker compose build --no-cache'
alias dcu='docker compose up -d'
alias dcub='docker compose up --build -d'
alias dcd='docker compose down -v'
alias dcr='docker compose restart'
alias dps='docker ps'
alias dpa='docker ps -a'

# Clipboard operations
alias cpf='pbcopy <'
alias paf='pbpaste >'

# ==========================================
# fzf Configuration
# ==========================================
export FZF_DEFAULT_OPTS="
  --height 60%
  --layout=reverse
  --border
  --inline-info
  --preview-window=right:60%:wrap
  --bind 'ctrl-/:toggle-preview'
  --bind 'ctrl-u:preview-half-page-up'
  --bind 'ctrl-d:preview-half-page-down'
  --color=fg:#c0caf5,bg:#1a1b26,hl:#bb9af7
  --color=fg+:#c0caf5,bg+:#1f2335,hl+:#7dcfff
  --color=info:#7aa2f7,prompt:#7dcfff,pointer:#7dcfff
  --color=marker:#9ece6a,spinner:#9ece6a,header:#9ece6a
"
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons --color=always {}'"
export FZF_CTRL_R_OPTS="--preview 'echo {}' --preview-window=down:3:wrap"

# fzf keybindings: Ctrl-R (history), Ctrl-O (cd)
if [[ -o zle ]]; then
  source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
  bindkey -r '^T'              # disable Ctrl-T (conflicts with Rectangle)
  bindkey '^O' fzf-cd-widget
  bindkey -M vicmd '^O' fzf-cd-widget
fi

# ==========================================
# ghq + gwq
# ==========================================
export GHQ_ROOT="$HOME/ghq"

# ghq × fzf: jump to repository (Ctrl-G)
cghq() {
  local repo
  repo="$(ghq list | fzf --preview 'eza --tree --level=3 --icons --color=always $(ghq root)/{}')" || return
  cd "$(ghq root)/$repo"
}
[[ -o zle ]] && bindkey -s '^G' 'cghq\n'

# git switch branch with fzf (Ctrl-B)
git-switch-fzf() {
  git swf
}
[[ -o zle ]] && bindkey -s '^B' 'git-switch-fzf\n'

# gwq wrapper: auto-create symlinks after 'gwq add'
gwq() {
  # Capture worktree count before
  local before_count=0
  if [[ "$1" == "add" ]]; then
    before_count=$(command gwq list --json 2>/dev/null | grep -c '"path"' || echo 0)
  fi

  # Run original gwq
  command gwq "$@"
  local ret=$?

  # After 'gwq add', create symlinks for the new worktree
  if [[ $ret -eq 0 && "$1" == "add" ]]; then
    local after_count=$(command gwq list --json 2>/dev/null | grep -c '"path"' || echo 0)
    if (( after_count > before_count )); then
      # Get main and newest worktree from JSON
      local json=$(command gwq list --json 2>/dev/null)
      local main_dir=$(echo "$json" | jq -r '.[] | select(.is_main == true) | .path')
      local new_dir=$(echo "$json" | jq -r 'sort_by(.created_at) | last | .path')

      if [[ -n "$main_dir" && -n "$new_dir" && "$main_dir" != "$new_dir" ]]; then
        _gwq_create_links "$main_dir" "$new_dir"
      fi
    fi
  fi

  return $ret
}

# Helper: create symlinks for git-ignored files (based on .git/info/exclude)
_gwq_create_links() {
  local main_dir="$1" target_dir="$2"
  local linked=()

  # Link target candidates (directories and files)
  local -a candidates=(
    "exclude"
    ".docs"
    ".claude"
    "CLAUDE.md"
    "AGENTS.md"
  )

  for item in "${candidates[@]}"; do
    local src="$main_dir/$item"
    local dst="$target_dir/$item"

    [[ -e "$src" ]] || continue

    if git -C "$main_dir" check-ignore -q "$item" 2>/dev/null; then
      # Whole item is git-ignored -> link it
      [[ -e "$dst" && ! -L "$dst" ]] && rm -rf "$dst"
      ln -sfn "$src" "$dst"
      linked+=("$item")
    elif [[ -d "$src" && ! -d "$dst" ]]; then
      # Directory exists in main but not in worktree (not checked out) -> link whole dir
      ln -sfn "$src" "$dst"
      linked+=("$item/")
    elif [[ -d "$src" && -d "$dst" ]]; then
      # Both exist: link only git-ignored files inside
      for f in "$src"/*; do
        [[ -e "$f" ]] || continue
        local fname="$(basename "$f")"
        local rel_path="$item/$fname"
        if git -C "$main_dir" check-ignore -q "$rel_path" 2>/dev/null; then
          ln -sfn "$f" "$dst/$fname"
          linked+=("$rel_path")
        fi
      done
    fi
  done

  if (( ${#linked[@]} > 0 )); then
    echo "Linked: ${linked[*]}"
  else
    echo "No files to link"
  fi
}

# ==========================================
# Machine-specific config
# ==========================================
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
