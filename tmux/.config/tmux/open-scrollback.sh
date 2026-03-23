#!/bin/sh
f=$(mktemp /tmp/tmux-scrollback.XXXXXX)
tmux capture-pane -epS - > "$f"
tmux new-window "/opt/homebrew/bin/nvim --clean \
  -c 'luafile ~/.config/tmux/scrollback-pager.lua' \
  -c 'terminal cat $f; rm $f; tail -f /dev/null'"
