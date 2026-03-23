#!/bin/bash
# PostToolUse hook: notify implementation CC pane when a review file is written/edited
# Triggered by Write|Edit tools targeting reviews/ directory

input=$(cat 2>/dev/null) || exit 0
[[ -z "$input" ]] && exit 0

tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
[[ "$tool_name" != "Write" && "$tool_name" != "Edit" ]] && exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[[ ! "$file_path" =~ reviews/ ]] && exit 0

# Extract reviewer name from file
reviewer=""
if [[ "$file_path" =~ /cc-rev\.md$ ]]; then
  reviewer="cc-rev"
elif [[ "$file_path" =~ /codex\.md$ ]]; then
  reviewer="codex"
else
  exit 0
fi

# Extract branch name and relative path from file path
# reviews/{branch}/codex.md → branch = {branch}
rel_path="${file_path#*reviews/}"
branch="${rel_path%%/*}"
rel_path="reviews/${rel_path}"

msg="${rel_path} に${reviewer}からレビューが届いたのだ。内容を確認し、以下の内容が妥当であるか客観的に分析してユーザに見解を述べて。"

# Try branch-named session first, fall back to "dev" session
tmux send-keys -t "${branch}:.impl" "$msg" Enter 2>/dev/null ||
tmux send-keys -t "dev:.impl" "$msg" Enter 2>/dev/null || true
