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
setopt IGNORE_EOF           # Ctrl+D でシェルを終了しない

# コマンド履歴
HISTSIZE=10000
SAVEHIST=10000
setopt EXTENDED_HISTORY     # 実行時刻も記録
setopt INC_APPEND_HISTORY   # 実行ごとに即保存
setopt HIST_IGNORE_SPACE    # スペース始まりは履歴に残さない
setopt HIST_IGNORE_ALL_DUPS # 重複は最新のみ残す
setopt HIST_REDUCE_BLANKS   # 余分な空白を削除

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
typeset -U path PATH  # PATH の重複を自動排除

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH=/opt/homebrew/bin:$PATH
export PATH="$HOME/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# rust
export PATH="$HOME/.cargo/bin:$PATH"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# golang
export GOTOOLCHAIN=auto

# ==========================================
# Git hooks
# ==========================================
if [[ -f "$HOME/.git-hooks.zsh" ]]; then
  source "$HOME/.git-hooks.zsh"
fi

# ==========================================
# Rust Development
# ==========================================
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

# ==========================================
# Interactive Shell Only
# ==========================================
[[ -o interactive ]] || return

# ==========================================
# Completion (deferred)
# ==========================================
# Homebrew の補完を有効化
FPATH="/opt/homebrew/share/zsh/site-functions:$FPATH"
fpath+=~/.zfunc
autoload -Uz compinit

# プロンプト表示後に compinit を遅延実行
_deferred_compinit() {
  unfunction _deferred_compinit
  compinit  # -C は使わない（補完定義が少ないためキャッシュ効果が薄い）
  [[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
}
zmodload zsh/sched
sched +0 _deferred_compinit

# 補完の表示設定
zstyle ':completion:*' menu select                    # メニュー選択を有効化
zstyle ':completion:*' verbose yes                    # 詳細表示
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'  # 説明を黄色で表示
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}'  # 大文字小文字を無視

# zsh-autosuggestions
[[ -f /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

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

# Directory operations
alias mkdir='mkdir -p'
alias mkd='mkdir -p'

# Docker aliases
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
[[ -f /opt/homebrew/opt/fzf/shell/key-bindings.zsh ]] && \
  source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
bindkey '^O' fzf-cd-widget   # Ctrl-O でディレクトリ移動

# ==========================================
# ghq
# ==========================================
export GHQ_ROOT="$HOME/ghq"

# ghq × fzf: リポジトリへジャンプ (Ctrl-G)
cghq() {
  local repo
  repo="$(ghq list | fzf --preview 'eza --tree --level=3 --icons --color=always $(ghq root)/{}')" || return
  cd "$(ghq root)/$repo"
}
bindkey -s '^G' 'cghq\n'
