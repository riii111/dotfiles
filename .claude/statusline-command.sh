#!/usr/bin/env bash
# Thin wrapper: auto-build Go statusline if stale, then exec it.
set -euo pipefail

SELF="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${BASH_SOURCE[0]}")"
DIR="$(cd "$(dirname "$SELF")/statusline" && pwd)"
BIN="$DIR/statusline-go"

# Rebuild if binary is missing or older than any .go / go.mod
needs_build() {
  [ ! -x "$BIN" ] && return 0
  for src in "$DIR"/*.go "$DIR"/go.mod; do
    [ "$src" -nt "$BIN" ] && return 0
  done
  return 1
}

if needs_build; then
  export PATH="/opt/homebrew/bin:/usr/local/go/bin:$PATH"
  go build -o "$BIN" "$DIR" 2>/dev/null || {
    printf '🤖 (build failed)'
    exit 0
  }
fi

exec "$BIN"
