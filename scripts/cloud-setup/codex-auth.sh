#!/usr/bin/env bash
# The environment's variables reach Claude Code's hooks but not the setup script, so the Codex login
# held in CODEX_AUTH_B64 is written at session start. It prints nothing.
auth="${CODEX_HOME:-$HOME/.codex}/auth.json"
[[ -s $auth || -z ${CODEX_AUTH_B64:-} ]] && exit 0
mkdir -p "$(dirname "$auth")"
umask 077
written=$(mktemp "$auth.XXXXXX") || exit 0
if printf %s "$CODEX_AUTH_B64" | base64 -d >"$written" 2>/dev/null; then
	mv -f "$written" "$auth"
else
	rm -f "$written"
fi
exit 0
