#!/usr/bin/env bash
# Claude Code statusline script
# Reads JSON from stdin, outputs 3-line ANSI-colored status

set -euo pipefail

# ── Colors ──
GREEN='\033[38;2;151;201;195m'   # #97C9C3
YELLOW='\033[38;2;229;192;123m'  # #E5C07B
RED='\033[38;2;224;108;117m'     # #E06C75
GRAY='\033[38;2;74;88;92m'       # #4A585C
RESET='\033[0m'

# ── Read stdin JSON ──
INPUT=$(cat)

MODEL_ID=$(echo "$INPUT" | jq -r '.model.id // ""')
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "Unknown"')
CTX_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0')
LINES_ADD=$(echo "$INPUT" | jq -r '.cost.total_lines_added // 0')
LINES_DEL=$(echo "$INPUT" | jq -r '.cost.total_lines_removed // 0')
COST_USD=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0')
DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
CWD=$(echo "$INPUT" | jq -r '.cwd // .workspace.current_dir // "."')

# ── Git branch ──
GIT_BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")

# ── Format duration ──
format_duration() {
  local ms=$1
  local total_sec=$(( ms / 1000 ))
  local hours=$(( total_sec / 3600 ))
  local mins=$(( (total_sec % 3600) / 60 ))
  if (( hours > 0 )); then
    printf "%dh%02dm" "$hours" "$mins"
  else
    printf "%dm" "$mins"
  fi
}

# ── Color by percentage ──
color_for_pct() {
  local pct=$1
  if (( pct < 50 )); then
    printf '%s' "$GREEN"
  elif (( pct < 80 )); then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$RED"
  fi
}

# ── Progress bar (10 segments) ──
progress_bar() {
  local pct=$1
  local filled=$(( (pct + 5) / 10 ))
  (( filled > 10 )) && filled=10
  (( filled < 0 )) && filled=0
  local empty=$(( 10 - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="▰"; done
  for ((i=0; i<empty; i++)); do bar+="▱"; done
  printf '%s' "$bar"
}

# ── Rate limit info ──
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360

fetch_usage() {
  local now
  now=$(date +%s)

  if [[ -f "$CACHE_FILE" ]]; then
    local cached_at
    cached_at=$(jq -r '.cached_at // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
    local age=$(( now - cached_at ))
    if (( age < CACHE_TTL )); then
      cat "$CACHE_FILE"
      return 0
    fi
  fi

  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
    | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null || true)

  if [[ -z "$token" ]]; then
    echo '{"error":true,"cached_at":'"$now"'}'
    return 1
  fi

  local resp
  resp=$(curl -sf -m 5 \
    -H "Authorization: Bearer $token" \
    https://api.anthropic.com/api/oauth/usage 2>/dev/null || true)

  if [[ -z "$resp" ]] || echo "$resp" | jq -e '.type == "error"' >/dev/null 2>&1; then
    local err_json='{"error":true,"cached_at":'"$now"'}'
    echo "$err_json" > "$CACHE_FILE"
    echo "$err_json"
    return 1
  fi

  echo "$resp" | jq --argjson ts "$now" '. + {cached_at: $ts}' > "$CACHE_FILE"
  cat "$CACHE_FILE"
}

USAGE_JSON=$(fetch_usage 2>/dev/null || echo '{"error":true}')
HAS_ERROR=$(echo "$USAGE_JSON" | jq -r '.error // false' 2>/dev/null)

if [[ "$HAS_ERROR" != "true" ]]; then
  FIVE_HR_UTIL=$(echo "$USAGE_JSON" | jq -r '.five_hour.utilization // 0' 2>/dev/null)
  SEVEN_DAY_UTIL=$(echo "$USAGE_JSON" | jq -r '.seven_day.utilization // 0' 2>/dev/null)
  FIVE_HR_RESET=$(echo "$USAGE_JSON" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
  SEVEN_DAY_RESET=$(echo "$USAGE_JSON" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)

  FIVE_HR_PCT=$(awk "BEGIN { printf \"%d\", $FIVE_HR_UTIL * 100 }")
  SEVEN_DAY_PCT=$(awk "BEGIN { printf \"%d\", $SEVEN_DAY_UTIL * 100 }")

  if [[ -n "$FIVE_HR_RESET" ]]; then
    FIVE_HR_RESET_FMT=$(TZ=Asia/Tokyo date -j -f "%Y-%m-%dT%H:%M:%S" "${FIVE_HR_RESET%%.*}" "+%-I%p" 2>/dev/null \
      || TZ=Asia/Tokyo date -d "$FIVE_HR_RESET" "+%-I%p" 2>/dev/null \
      || echo "??")
  else
    FIVE_HR_RESET_FMT="??"
  fi

  if [[ -n "$SEVEN_DAY_RESET" ]]; then
    SEVEN_DAY_RESET_FMT=$(TZ=Asia/Tokyo date -j -f "%Y-%m-%dT%H:%M:%S" "${SEVEN_DAY_RESET%%.*}" "+%b %-d at %-I%p" 2>/dev/null \
      || TZ=Asia/Tokyo date -d "$SEVEN_DAY_RESET" "+%b %-d at %-I%p" 2>/dev/null \
      || echo "??")
  else
    SEVEN_DAY_RESET_FMT="??"
  fi
else
  FIVE_HR_PCT=0
  SEVEN_DAY_PCT=0
  FIVE_HR_RESET_FMT="N/A"
  SEVEN_DAY_RESET_FMT="N/A"
fi

# ── Model display name ──
if [[ "$MODEL_ID" == *"opus"* ]]; then
  MODEL_DISPLAY="Opus 4.6"
elif [[ "$MODEL_ID" == *"sonnet"* ]]; then
  MODEL_DISPLAY="Sonnet 4.6"
elif [[ "$MODEL_ID" == *"haiku"* ]]; then
  MODEL_DISPLAY="Haiku 4.5"
else
  MODEL_DISPLAY="$MODEL"
fi

# ── Format values ──
COST_FMT=$(awk "BEGIN { printf \"$%.2f\", $COST_USD }")
DURATION_FMT=$(format_duration "$DURATION_MS")
CTX_COLOR=$(color_for_pct "$CTX_PCT")
FIVE_COLOR=$(color_for_pct "$FIVE_HR_PCT")
SEVEN_COLOR=$(color_for_pct "$SEVEN_DAY_PCT")

# ── Line 1: model │ context │ lines │ branch │ cost │ duration ──
printf '🤖 %s %b│%b %b📊 %d%%%b %b│%b ✏️  +%d/-%d %b│%b 🔀 %s %b│%b 💰 %s %b│%b ⏱  %s\n' \
  "$MODEL_DISPLAY" "$GRAY" "$RESET" "$CTX_COLOR" "$CTX_PCT" "$RESET" "$GRAY" "$RESET" \
  "$LINES_ADD" "$LINES_DEL" "$GRAY" "$RESET" "$GIT_BRANCH" \
  "$GRAY" "$RESET" "$COST_FMT" "$GRAY" "$RESET" "$DURATION_FMT"

# ── Line 2: 5h rate limit ──
printf '%b⏱ 5h  %s  %3d%%%b  Resets %s (Asia/Tokyo)\n' \
  "$FIVE_COLOR" "$(progress_bar "$FIVE_HR_PCT")" "$FIVE_HR_PCT" "$RESET" "$FIVE_HR_RESET_FMT"

# ── Line 3: 7d rate limit ──
printf '%b📅 7d  %s  %3d%%%b  Resets %s (Asia/Tokyo)\n' \
  "$SEVEN_COLOR" "$(progress_bar "$SEVEN_DAY_PCT")" "$SEVEN_DAY_PCT" "$RESET" "$SEVEN_DAY_RESET_FMT"
