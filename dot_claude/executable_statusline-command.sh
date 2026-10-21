#!/usr/bin/env bash
# Thin wrapper: auto-build Go statusline if stale, then exec it.
set -euo pipefail

SELF="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "${BASH_SOURCE[0]}")"
DIR="$(cd "$(dirname "$SELF")/statusline" && pwd)"
BIN="$DIR/statusline-go"
HASH_FILE="$DIR/.src-hash"

# Prefer the managed compiler even when launched outside an interactive shell.
export PATH="$HOME/.nix-profile/bin:$PATH"
export GOTOOLCHAIN=local
GO_VERSION=$(go env GOVERSION 2>/dev/null) || {
  printf '🤖 (Go unavailable)'
  exit 0
}

source_hash() {
  { printf '%s\n' "$GO_VERSION"; cat "$DIR"/*.go "$DIR"/go.mod "$DIR"/go.sum; } | shasum -a 256 | cut -d' ' -f1
}

# Rebuild if binary missing, source newer than binary, or content hash changed
needs_build() {
  [ ! -x "$BIN" ] && return 0
  for src in "$DIR"/*.go "$DIR"/go.mod "$DIR"/go.sum; do
    [ "$src" -nt "$BIN" ] && return 0
  done
  [ ! -f "$HASH_FILE" ] && return 0
  local cur
  cur=$(source_hash)
  [ "$cur" != "$(head -1 "$HASH_FILE")" ]
}

if needs_build; then
  go build -C "$DIR" -o "$BIN" . 2>/dev/null || {
    printf '🤖 (build failed)'
    exit 0
  }
  source_hash > "$HASH_FILE"
fi

exec "$BIN"
