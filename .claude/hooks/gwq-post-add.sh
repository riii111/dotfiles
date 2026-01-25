#!/bin/bash
# PostToolUse hook: auto-create symlinks after 'gwq add'
#
# Input (stdin): JSON with tool_name, tool_input, tool_response
# Output: nothing (side effect only)

set -euo pipefail

# Read input from stdin
input=$(cat)

# Check if this is a Bash tool call with 'gwq add'
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

if [[ ! "$command" =~ ^gwq\ add ]]; then
  exit 0
fi

# Check if the command succeeded (look for "Created worktree" in response)
tool_response=$(echo "$input" | jq -r '.tool_response // empty')
if [[ ! "$tool_response" =~ "Created worktree" ]]; then
  exit 0
fi

# Get main and newest worktree from gwq list
json=$(gwq list --json 2>/dev/null) || exit 0
main_dir=$(echo "$json" | jq -r '.[] | select(.is_main == true) | .path')
new_dir=$(echo "$json" | jq -r 'sort_by(.created_at) | last | .path')

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
