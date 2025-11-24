# ==========================================
# Zsh Startup Caching Mechanism
# ==========================================
# Cache slow initialization commands to improve startup speed
ZSHRC_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
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
# Prompt
# ==========================================
PS1="%1~ %# "

# ==========================================
# Environment Variables
# ==========================================
# Editors
export EDITOR=nvim
export GIT_EDITOR=nvim
export VISUAL=nvim
export MANPAGER='nvim +Man!'

# XDG Base Directory
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# ==========================================
# Modern CLI Tools Aliases
# ==========================================
# Use modern replacements for traditional Unix tools
alias cat='bat'
alias ls='eza'
alias ll='eza -hl'
alias la='eza -hla'
alias lt='eza --tree'
alias lg='eza -hlFg'

# ==========================================
# Basic Aliases
# ==========================================
alias vim='nvim'
alias v='nvim'
alias nv='nvim'
alias clr='clear'
alias o='open'

# Directory operations
alias mkdir='mkdir -p'
alias mkd='mkdir -p'

# Docker aliases
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcub='docker compose up --build'
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
# Basic fzf options only (no keybindings to avoid conflicts)
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

# Use fd instead of find for fzf (respects .gitignore)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'

# ==========================================
# Git hooks
# ==========================================
if [[ -f "$HOME/.git-hooks.zsh" ]]; then
  source "$HOME/.git-hooks.zsh"
fi
