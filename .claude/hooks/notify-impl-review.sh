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

# Extract relative path for the notification message
rel_path="${file_path#*reviews/}"
rel_path="reviews/${rel_path}"

# Notify the implementation CC pane via tmux (fail silently if tmux/pane unavailable)
tmux send-keys -t impl \
  "${rel_path} に${reviewer}からレビューが届いたのだ。内容を確認し、以下の内容が妥当であるか客観的に分析してユーザに見解を述べて。" Enter \
  2>/dev/null || true
