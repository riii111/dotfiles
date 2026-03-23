#!/bin/bash
set -e

# Snapshot unstaged files before re-add
before=$(git diff --name-only)

# Sync edited managed files (destination → source)
chezmoi re-add

# Stage only files that re-add introduced (not previously unstaged)
git diff --name-only | while read -r f; do
  echo "$before" | grep -qFx "$f" || git add -- "$f"
done
