#!/bin/bash
# PostToolUse hook: auto-create symlinks after 'git worktree add'

input=$(cat 2>/dev/null) || exit 0
[[ -z "$input" ]] && exit 0

tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[[ "$tool_name" != "Bash" ]] && exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ ! "$command" =~ ^git\ worktree\ add ]] && exit 0

tool_response=$(echo "$input" | jq -r '.tool_response // empty' 2>/dev/null) || exit 0
[[ ! "$tool_response" =~ "Preparing worktree" ]] && exit 0

# bash 3.2 compatible
worktree_paths=$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}') || exit 0
[[ -z "$worktree_paths" ]] && exit 0

worktree_count=$(echo "$worktree_paths" | wc -l | tr -d ' ')
(( worktree_count < 2 )) && exit 0

# first = main, last = newest
main_dir=$(echo "$worktree_paths" | head -1)
new_dir=$(echo "$worktree_paths" | tail -1)

[[ -z "$main_dir" || -z "$new_dir" || "$main_dir" == "$new_dir" ]] && exit 0

linked=()
candidates=("exclude" ".docs" ".claude" "CLAUDE.md" "AGENTS.md")

for item in "${candidates[@]}"; do
  src="$main_dir/$item"
  dst="$new_dir/$item"

  [[ -e "$src" ]] || continue

  if git -C "$main_dir" check-ignore -q "$item" 2>/dev/null; then
    [[ -e "$dst" && ! -L "$dst" ]] && rm -rf "$dst"
    ln -sfn "$src" "$dst"
    linked+=("$item")
  elif [[ -d "$src" && ! -d "$dst" ]]; then
    ln -sfn "$src" "$dst"
    linked+=("$item/")
  elif [[ -d "$src" && -d "$dst" ]]; then
    # link only git-ignored files inside
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
