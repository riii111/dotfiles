#!/bin/bash
set -e

# Skip if no managed files have drifted (fast path: ~0.02s)
if [ -z "$(chezmoi diff --reverse 2>/dev/null)" ]; then
  exit 0
fi

# Snapshot unstaged files before re-add
before=$(git diff --name-only)

# Sync edited managed files (destination → source)
chezmoi re-add

# Stage only files that re-add introduced (not previously unstaged)
git diff --name-only | while read -r f; do
  echo "$before" | grep -qFx "$f" || git add -- "$f"
done
