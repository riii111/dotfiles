#!/bin/sh
set -eu

NVIM="$(command -v nvim || true)"
[ -n "$NVIM" ] || { echo "nvim not found in PATH" >&2; exit 1; }

f=$(mktemp /tmp/tmux-scrollback.XXXXXX)
tmux capture-pane -epS - > "$f"
tmux split-window -Z "$NVIM --clean \
  -c 'luafile ~/.config/tmux/scrollback-pager.lua' \
  -c 'terminal cat $f; rm $f; tail -f /dev/null'"
