#!/usr/bin/env bash
# Thin wrapper: auto-build Go statusline if stale, then exec it.
set -euo pipefail

SELF="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${BASH_SOURCE[0]}")"
DIR="$(cd "$(dirname "$SELF")/statusline" && pwd)"
BIN="$DIR/statusline-go"
HASH_FILE="$DIR/.src-hash"

# Rebuild if binary missing, source newer than binary, or content hash changed
needs_build() {
  [ ! -x "$BIN" ] && return 0
  for src in "$DIR"/*.go "$DIR"/go.mod; do
    [ "$src" -nt "$BIN" ] && return 0
  done
  [ ! -f "$HASH_FILE" ] && return 0
  local cur
  cur=$(cat "$DIR"/*.go "$DIR"/go.mod 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
  [ "$cur" != "$(head -1 "$HASH_FILE")" ]
}

if needs_build; then
  export PATH="/opt/homebrew/bin:/usr/local/go/bin:$PATH"
  go build -C "$DIR" -o "$BIN" . 2>/dev/null || {
    printf '🤖 (build failed)'
    exit 0
  }
  cat "$DIR"/*.go "$DIR"/go.mod 2>/dev/null | shasum -a 256 | cut -d' ' -f1 > "$HASH_FILE"
fi

exec "$BIN"
