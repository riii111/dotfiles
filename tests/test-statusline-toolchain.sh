#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/home/.nix-profile/bin" "$scratch/statusline" "$scratch/fallback"
cp "$root/dot_claude/executable_statusline-command.sh" "$scratch/command.sh"
printf 'module test\n' > "$scratch/statusline/go.mod"
touch "$scratch/statusline/main.go" "$scratch/statusline/go.sum"
cat > "$scratch/home/.nix-profile/bin/go" <<'GO'
#!/usr/bin/env bash
set -eu
if [ "$1" = env ]; then
  cat "$TEST_ROOT/version"
else
  echo build >> "$TEST_ROOT/builds"
  printf '#!/bin/sh\necho statusline\n' > "$5"
  chmod +x "$5"
fi
GO
cat > "$scratch/fallback/go" <<'GO'
#!/bin/sh
exit 99
GO
chmod +x "$scratch/home/.nix-profile/bin/go" "$scratch/fallback/go"
export TEST_ROOT="$scratch"
export HOME="$scratch/home"
export PATH="$scratch/fallback:$PATH"
echo go1.27.2 > "$scratch/version"
bash "$scratch/command.sh" > /dev/null
bash "$scratch/command.sh" > /dev/null
test "$(wc -l < "$scratch/builds" | tr -d ' ')" = 1
echo go1.27.3 > "$scratch/version"
bash "$scratch/command.sh" > /dev/null
test "$(wc -l < "$scratch/builds" | tr -d ' ')" = 2
printf 'changed\n' > "$scratch/statusline/go.sum"
bash "$scratch/command.sh" > /dev/null
test "$(wc -l < "$scratch/builds" | tr -d ' ')" = 3
echo 'statusline compiler/cache tests passed'
