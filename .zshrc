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

# Set terminal title for WezTerm right status
# Format: "repo::ref::flags" (flags: d=dirty, D=detached, w=worktree, R=rebase, M=merge, C=cherry-pick)
__TERM_TITLE_LAST=""

_find_git_root() {
  local dir="${PWD:A}"

  while [[ "$dir" != "/" ]]; do
    [[ -e "$dir/.git" ]] && print -r -- "$dir" && return 0
    dir="${dir:h}"
  done

  return 1
}

_resolve_git_dir() {
  local root="$1"
  local git_entry="$root/.git"

  if [[ -d "$git_entry" ]]; then
    print -r -- "$git_entry"
    return 0
  fi

  if [[ -f "$git_entry" ]]; then
    local git_dir
    IFS= read -r git_dir < "$git_entry"
    git_dir="${git_dir#gitdir: }"
    [[ "$git_dir" = /* ]] || git_dir="$root/$git_dir"
    print -r -- "${git_dir:A}"
    return 0
  fi

  return 1
}

_print_terminal_title() {
  local title="$1"
  [[ "$title" == "$__TERM_TITLE_LAST" ]] && return 0
  __TERM_TITLE_LAST="$title"
  printf '\e]2;%s\a' "$title"
}

_set_terminal_title() {
  local dir="${PWD##*/}"
  dir="${dir:-/}"

  local repo_root
  repo_root=$(_find_git_root) || {
    _print_terminal_title "$dir"
    return
  }

  local repo
  repo="${repo_root:t}"

  local status_output
  status_output=$(command git -C "$repo_root" status --porcelain=v2 --branch 2>/dev/null) || {
    _print_terminal_title "$dir"
    return
  }

  local ref=""
  local oid=""
  local flags=""
  local line
  while IFS= read -r line; do
    case "$line" in
      "# branch.head "*)
        ref="${line#\# branch.head }"
        ;;
      "# branch.oid "*)
        oid="${line#\# branch.oid }"
        ;;
      \#*)
        ;;
      *)
        flags="${flags}d"
        ;;
    esac
  done <<< "$status_output"

  if [[ "$ref" == "(detached)" ]]; then
    ref="${oid[1,7]}"
    flags="${flags}D"
  fi

  local git_dir
  git_dir=$(_resolve_git_dir "$repo_root") || {
    _print_terminal_title "${repo}::${ref:-unknown}${flags:+::$flags}"
    return
  }

  [[ -f "$repo_root/.git" ]] && flags="${flags}w"
  [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]] && flags="${flags}R"
  [[ -f "$git_dir/MERGE_HEAD" ]] && flags="${flags}M"
  [[ -f "$git_dir/CHERRY_PICK_HEAD" ]] && flags="${flags}C"

  _print_terminal_title "${repo}::${ref:-unknown}${flags:+::$flags}"
}

git() {
  command git "$@"
  local ret=$?
  _set_terminal_title
  return $ret
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _set_terminal_title
_set_terminal_title

# ==========================================
# Environment Variables
# ==========================================
# Editors
export EDITOR=nvim
export GIT_EDITOR=nvim
export VISUAL=nvim
export MANPAGER='nvim +Man!'

# Docker (Colima)
export DOCKER_HOST="unix://${XDG_CONFIG_HOME}/colima/default/docker.sock"

# ==========================================
# Homebrew (static: replaces slow `eval "$(brew shellenv)"`)
# ==========================================
export HOMEBREW_PREFIX="/opt/homebrew"
export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
export HOMEBREW_REPOSITORY="/opt/homebrew"
export MANPATH="${MANPATH:+$MANPATH:}/opt/homebrew/share/man:"
export INFOPATH="/opt/homebrew/share/info:${INFOPATH:-}"

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
for _gcmd in gcloud gsutil bq; do
  eval "${_gcmd}() {
    unfunction gcloud gsutil bq 2>/dev/null
    source /opt/homebrew/share/google-cloud-sdk/path.zsh.inc
    source /opt/homebrew/share/google-cloud-sdk/completion.zsh.inc
    ${_gcmd} \"\$@\"
  }"
done
unset _gcmd

# golang
export GOTOOLCHAIN=auto

# rust
export PATH="$HOME/.cargo/bin:$PATH"

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

  # Use compinit -C unless fpath membership, dir contents, or user files changed
  local _fpath_cache="$HOME/.zcompdump.fpath"
  local _fpath_sig="${(pj:\n:)fpath}"
  local _compinit_flags=(-C)
  if [[ ! -f ~/.zcompdump ]] || [[ ! -f "$_fpath_cache" ]] || [[ "$(<$_fpath_cache)" != "$_fpath_sig" ]]; then
    _compinit_flags=()
  else
    for _fp in $fpath; do
      if [[ "$_fp" -nt ~/.zcompdump ]]; then
        _compinit_flags=(); break
      fi
    done
    if (( $#_compinit_flags )) && [[ -d ~/.zfunc ]]; then
      for _f in ~/.zfunc/*(N); do
        if [[ "$_f" -nt ~/.zcompdump ]]; then
          _compinit_flags=(); break
        fi
      done
    fi
  fi
  compinit $_compinit_flags[@]
  printf '%s\n' $fpath > "$_fpath_cache"
  [[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"

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
# zsh-abbr (deferred: loads on first text input)
# ==========================================
export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml"

_deferred_abbr_init() {
  unfunction _deferred_abbr_init
  source /opt/homebrew/share/zsh-abbr/zsh-abbr.zsh

  # Modern CLI Tools (--force: override same-name system commands)
  abbr -S -qq --force cat='bat'
  abbr -S -qq --force ls='eza'
  abbr -S -qq ll='eza -hl'
  abbr -S -qq la='eza -hla'
  abbr -S -qq lt='eza --tree'
  abbr -S -qq llg='eza -hlFg'

  # Basic
  abbr -S -qq --force vim='nvim'
  abbr -S -qq v='nvim'
  abbr -S -qq nv='nvim'
  abbr -S -qq clr='clear'
  abbr -S -qq --force o='open'
  abbr -S -qq lg='lazygit'
  abbr -S -qq --force mkdir='mkdir -p'
  abbr -S -qq mkd='mkdir -p'

  # Docker
  abbr -S -qq --force dc='docker compose'
  abbr -S -qq dcb='docker compose build'
  abbr -S -qq dcbn='docker compose build --no-cache'
  abbr -S -qq dcu='docker compose up -d'
  abbr -S -qq dcub='docker compose up --build -d'
  abbr -S -qq dcd='docker compose down -v'
  abbr -S -qq dcr='docker compose restart'
  abbr -S -qq dps='docker ps'
  abbr -S -qq dpa='docker ps -a'

  # Clipboard
  abbr -S -qq cpf='pbcopy <'
  abbr -S -qq paf='pbpaste >'
}

_abbr_on_first_input() {
  zle -A _abbr_original_self_insert self-insert
  unfunction _abbr_on_first_input 2>/dev/null
  _deferred_abbr_init
  zle _abbr_original_self_insert
}

if [[ -o zle ]]; then
  zle -A self-insert _abbr_original_self_insert
  zle -N self-insert _abbr_on_first_input
fi

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
# ghq + git worktree
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

# ==========================================
# Claude Code settings merge wrapper
# ==========================================
claude() {
  local base="${HOME}/.claude/settings.base.json"
  local local_conf="${HOME}/.claude/settings.local.json"
  local out="${HOME}/.claude/settings.json"

  if [[ ! -f "$out" || "$base" -nt "$out" || "$local_conf" -nt "$out" ]]; then
    if [[ ! -f "$base" ]]; then
      echo "Error: $base not found. Symlink from dotfiles." >&2
      return 1
    fi
    if [[ ! -f "$local_conf" ]]; then
      echo "Error: $local_conf not found. Copy from settings.local.json.example" >&2
      return 1
    fi
    if ! jq -s '
      .[0] as $b | .[1] as $l |
      ($b * $l) |
      .permissions.allow = (
        ($b.permissions.allow // [] | map(select(contains("[[YOUR_USER_NAME]]") | not))) +
        ($l.permissions.allow // [])
      )
    ' "$base" "$local_conf" > "$out"; then
      echo "Error: Failed to merge settings.json" >&2
      return 1
    fi
  fi

  command claude "$@"
}

# Launch Claude Code as implementation AI with tmux pane named "impl"
# Usage: cc-impl [session-name] [claude options...]
# Examples:
#   cc-impl                → session "dev"
#   cc-impl feat-auth      → session "feat-auth"
#   cc-impl --resume       → session "dev", resume
#   cc-impl feat-auth --resume → session "feat-auth", resume
cc-impl() {
  local session="dev"
  # First non-flag arg is session name
  if [[ $# -gt 0 && "$1" != -* ]]; then
    session="$1"
    shift
  fi

  if [[ -n "$TMUX" ]]; then
    tmux select-pane -T impl
  else
    # Clear git info title before tmux takes over the pane
    printf '\e]2;claude\a'
    tmux new-session -s "$session" -n dev \; select-pane -T impl \; send-keys "cc-impl $session $*" Enter
    return
  fi
  claude "$@"
}

# ==========================================
# Flyway Migration Search
# ==========================================
# Search all deploy-stg branches for a Flyway migration version.
# Useful for diagnosing checksum mismatch errors during STG deployment.
find-migration() {
  if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    cat <<'HELP'
find-migration - Search deploy-stg branches for a Flyway migration version

USAGE
  find-migration [OPTIONS] <VERSION>

ARGS
  VERSION   Migration version prefix to search (e.g. V0524)

OPTIONS
  --no-fetch   Skip "git fetch" and use locally cached branches
  -h, --help   Show this help

EXAMPLES
  find-migration V0524             # find which deploy-stg branches have V0524
  find-migration V052              # broader search covering V0520-V0529
  find-migration --no-fetch V0524  # skip fetch for faster re-runs

WHEN TO USE
  Flyway reports "Migration checksum mismatch for migration version XXXX"
  during STG deployment. This means the same version number was previously
  applied to the DB with different file contents.

  Run this command with the version from the error to find which past
  deploy-stg branch introduced the conflicting migration and who committed it.

SEE ALSO
  Learning: ~/.claude/cache/learnings/contract-one/flyway-checksum-mismatch-deploy-stg.md
HELP
    return 0
  fi

  local repo_root
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: not a git repository" >&2
    return 1
  }

  local do_fetch=true
  if [[ "$1" == "--no-fetch" ]]; then
    do_fetch=false
    shift
  fi

  local version="${1:?Usage: find-migration [--no-fetch] <VERSION>}"
  local migration_path="backend/database/src/main/resources/db/tenant/migration"

  if $do_fetch; then
    if ! git -C "$repo_root" fetch origin 'refs/heads/deploy-stg/*:refs/remotes/origin/deploy-stg/*' 2>/dev/null; then
      echo "Warning: fetch failed, using locally cached branches" >&2
    fi
  fi

  local found=false
  git -C "$repo_root" branch -r | rg -o 'origin/deploy-stg/\S+' | while read -r branch; do
    local hit=$(git -C "$repo_root" ls-tree --full-tree --name-only "$branch" -- "$migration_path/" 2>/dev/null | rg -F -- "$version")
    if [[ -n "$hit" ]]; then
      found=true
      echo "\033[1;33m=== ${branch#origin/} ===\033[0m"
      echo "$hit" | while read -r file; do
        echo "  ${file##*/}"
        git -C "$repo_root" log --format='  %C(yellow)%h%C(reset) %s (%an, %ad)' --date=short "$branch" -- \
          "$file" 2>/dev/null
      done
    fi
  done

  if ! $found; then
    echo "No matches for '$version' in any deploy-stg branch" >&2
  fi
}

# ==========================================
# Machine-specific config
# ==========================================
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
