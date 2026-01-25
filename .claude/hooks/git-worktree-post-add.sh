#!/bin/bash
# PostToolUse hook: auto-create symlinks after 'git worktree add'
#
# Input (stdin): JSON with tool_name, tool_input, tool_response
# Output: nothing (side effect only)

set -euo pipefail

# Read input from stdin
input=$(cat)

# Check if this is a Bash tool call with 'git worktree add'
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

if [[ ! "$command" =~ ^git\ worktree\ add ]]; then
  exit 0
fi

# Check if the command succeeded (look for "Preparing worktree" in response)
tool_response=$(echo "$input" | jq -r '.tool_response // empty')
if [[ ! "$tool_response" =~ "Preparing worktree" ]]; then
  exit 0
fi

# Parse worktrees from porcelain output (bash 3.2 compatible)
# Format: worktree <path>\nHEAD <hash>\nbranch <ref>\n\n...
worktree_paths=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}')
worktree_count=$(echo "$worktree_paths" | grep -c .)

if (( worktree_count < 2 )); then
  exit 0
fi

# First worktree is main, last is newest
main_dir=$(echo "$worktree_paths" | head -1)
new_dir=$(echo "$worktree_paths" | tail -1)

if [[ -z "$main_dir" || -z "$new_dir" || "$main_dir" == "$new_dir" ]]; then
  exit 0
fi

# Create symlinks for git-ignored files
linked=()
candidates=("exclude" ".docs" ".claude" "CLAUDE.md" "AGENTS.md")

for item in "${candidates[@]}"; do
  src="$main_dir/$item"
  dst="$new_dir/$item"

  [[ -e "$src" ]] || continue

  if git -C "$main_dir" check-ignore -q "$item" 2>/dev/null; then
    # Whole item is git-ignored -> link it
    [[ -e "$dst" && ! -L "$dst" ]] && rm -rf "$dst"
    ln -sfn "$src" "$dst"
    linked+=("$item")
  elif [[ -d "$src" && ! -d "$dst" ]]; then
    # Directory exists in main but not in worktree -> link whole dir
    ln -sfn "$src" "$dst"
    linked+=("$item/")
  elif [[ -d "$src" && -d "$dst" ]]; then
    # Both exist: link only git-ignored files inside
    for f in "$src"/*; do
      [[ -e "$f" ]] || continue
      fname="$(basename "$f")"
      rel_path="$item/$fname"
      if git -C "$main_dir" check-ignore -q "$rel_path" 2>/dev/null; then
        ln -sfn "$f" "$dst/$fname"
        linked+=("$rel_path")
      fi
    done
  fi
done

if (( ${#linked[@]} > 0 )); then
  echo "Linked: ${linked[*]}" >&2
fi
