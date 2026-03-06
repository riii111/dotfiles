#!/usr/bin/env bash
# Claude Code statusline script
# Reads JSON from stdin, outputs 3-line ANSI-colored status

# ── Colors ──
GREEN=$'\e[38;2;151;201;195m'
YELLOW=$'\e[38;2;229;192;123m'
RED=$'\e[38;2;224;108;117m'
GRAY=$'\e[38;2;74;88;92m'
DIM=$'\e[2m'
RESET=$'\e[0m'

# ── Read stdin JSON (eval-free, @tsv) ──
INPUT=$(cat)
IFS=$'\t' read -r MODEL_DISPLAY CTX_PCT LINES_ADD LINES_DEL CWD CC_VERSION < <(
  printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // "Unknown"),
    (.context_window.used_percentage // 0 | tostring),
    (.cost.total_lines_added // 0 | tostring),
    (.cost.total_lines_removed // 0 | tostring),
    (.cwd // ""),
    (.version // "0.0.0")
  ] | @tsv' 2>/dev/null
)

# ── Git branch ──
GIT_BRANCH=""
if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  GIT_BRANCH=$(git -C "$CWD" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

# ── Numeric validation ──
is_number() {
  printf '%s' "$1" | grep -qE '^[0-9]+(\.[0-9]+)?$'
}

# ── Color by percentage ──
color_for_pct() {
  local pct="$1"
  local ipct=0
  if is_number "$pct"; then
    ipct=$(printf "%.0f" "$pct" 2>/dev/null || echo 0)
  fi
  if [ "$ipct" -ge 80 ]; then
    printf '%s' "$RED"
  elif [ "$ipct" -ge 50 ]; then
    printf '%s' "$YELLOW"
  else
    printf '%s' "$GREEN"
  fi
}

# ── Progress bar (10 segments) ──
progress_bar() {
  local pct="$1"
  is_number "$pct" || pct=0
  local filled
  filled=$(awk "BEGIN{printf \"%d\", int($pct / 10 + 0.5)}")
  [ "$filled" -gt 10 ] && filled=10
  [ "$filled" -lt 0 ] && filled=0
  local bar=""
  for i in $(seq 1 10); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}▰"
    else
      bar="${bar}▱"
    fi
  done
  printf '%s' "$bar"
}

# ── Rate limit via Haiku probe (cached 360s) ──
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360
FIVE_HOUR_UTIL=""
FIVE_HOUR_RESET=""
SEVEN_DAY_UTIL=""
SEVEN_DAY_RESET=""

fetch_usage() {
  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
  [ -z "$token" ] && return 1

  local access_token
  if printf '%s' "$token" | jq -e . >/dev/null 2>&1; then
    access_token=$(printf '%s' "$token" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  else
    access_token="$token"
  fi
  [ -z "$access_token" ] && return 1

  local full_response
  full_response=$(curl -sD- --max-time 8 -o /dev/null \
    -H "Authorization: Bearer ${access_token}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: claude-code/${CC_VERSION:-0.0.0}" \
    -H "anthropic-beta: oauth-2025-04-20" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"h"}]}' \
    "https://api.anthropic.com/v1/messages" 2>/dev/null || true)
  [ -z "$full_response" ] && return 1

  local h5_util h5_reset h7_util h7_reset
  h5_util=$(printf '%s' "$full_response" | grep -i 'anthropic-ratelimit-unified-5h-utilization' | tr -d '\r' | awk '{print $2}')
  h5_reset=$(printf '%s' "$full_response" | grep -i 'anthropic-ratelimit-unified-5h-reset'       | tr -d '\r' | awk '{print $2}')
  h7_util=$(printf '%s' "$full_response" | grep -i 'anthropic-ratelimit-unified-7d-utilization' | tr -d '\r' | awk '{print $2}')
  h7_reset=$(printf '%s' "$full_response" | grep -i 'anthropic-ratelimit-unified-7d-reset'       | tr -d '\r' | awk '{print $2}')

  # Require numeric utilization value before writing cache
  is_number "$h5_util" || return 1

  # Atomic write with restricted permissions
  local old_umask tmp_cache
  old_umask=$(umask)
  umask 077
  tmp_cache=$(mktemp "${CACHE_FILE}.XXXXXX")
  umask "$old_umask"

  jq -n \
    --arg h5u "$h5_util" --arg h5r "$h5_reset" \
    --arg h7u "$h7_util" --arg h7r "$h7_reset" \
    '{five_hour_util: $h5u, five_hour_reset: $h5r, seven_day_util: $h7u, seven_day_reset: $h7r}' \
    > "$tmp_cache" && mv "$tmp_cache" "$CACHE_FILE" || rm -f "$tmp_cache"
  return 0
}

load_usage() {
  local data="$1"
  # Validate cache structure before reading
  if ! printf '%s' "$data" | jq -e 'has("five_hour_util")' >/dev/null 2>&1; then
    return 1
  fi
  IFS=$'\t' read -r FIVE_HOUR_UTIL FIVE_HOUR_RESET SEVEN_DAY_UTIL SEVEN_DAY_RESET < <(
    printf '%s' "$data" | jq -r '[
      (.five_hour_util  // ""),
      (.five_hour_reset // ""),
      (.seven_day_util  // ""),
      (.seven_day_reset // "")
    ] | @tsv' 2>/dev/null
  )
}

# ── Check cache validity ──
USE_CACHE=false
if [ -f "$CACHE_FILE" ]; then
  cache_mtime=$(stat -f '%m' "$CACHE_FILE" 2>/dev/null || stat -c '%Y' "$CACHE_FILE" 2>/dev/null || echo 0)
  cache_age=$(( $(date +%s) - cache_mtime ))
  if [ "$cache_age" -lt "$CACHE_TTL" ]; then
    USE_CACHE=true
  fi
fi

if $USE_CACHE; then
  load_usage "$(cat "$CACHE_FILE")"
else
  if fetch_usage; then
    load_usage "$(cat "$CACHE_FILE")"
  elif [ -f "$CACHE_FILE" ]; then
    load_usage "$(cat "$CACHE_FILE")"
  fi
fi

# ── Convert utilization (0.0-1.0) to percentage ──
to_pct() {
  local val="$1"
  [ -z "$val" ] || [ "$val" = "null" ] && echo "" && return
  is_number "$val" || { echo ""; return; }
  awk "BEGIN{printf \"%.0f\", $val * 100}"
}

FIVE_HR_PCT=$(to_pct "$FIVE_HOUR_UTIL")
SEVEN_DAY_PCT=$(to_pct "$SEVEN_DAY_UTIL")

# ── Format reset time (from epoch seconds) ──
format_epoch_time() {
  local epoch="$1"
  local format="$2"
  [ -z "$epoch" ] || [ "$epoch" = "0" ] && echo "" && return
  is_number "$epoch" || { echo ""; return; }
  local result
  result=$(TZ="Asia/Tokyo" date -j -f "%s" "$epoch" "$format" 2>/dev/null || \
           TZ="Asia/Tokyo" date -d "@${epoch}" "$format" 2>/dev/null || echo "")
  printf '%s' "$result" | sed 's/AM/am/;s/PM/pm/'
}

five_reset_display=""
if [ -n "$FIVE_HOUR_RESET" ] && [ "$FIVE_HOUR_RESET" != "0" ]; then
  five_reset_display="Resets $(format_epoch_time "$FIVE_HOUR_RESET" "+%-I%p") (Asia/Tokyo)"
fi

seven_reset_display=""
if [ -n "$SEVEN_DAY_RESET" ] && [ "$SEVEN_DAY_RESET" != "0" ]; then
  seven_reset_display="Resets $(format_epoch_time "$SEVEN_DAY_RESET" "+%b %-d at %-I%p") (Asia/Tokyo)"
fi

# ── Format context used% ──
ctx_pct_int=0
if [ -n "$CTX_PCT" ] && is_number "$CTX_PCT"; then
  ctx_pct_int=$(printf "%.0f" "$CTX_PCT" 2>/dev/null || echo 0)
fi

# ── Line 1: model │ context │ lines │ branch ──
SEP="${GRAY} │ ${RESET}"
ctx_color=$(color_for_pct "$ctx_pct_int")

line1="🤖 ${MODEL_DISPLAY}${SEP}${ctx_color}📊 ${ctx_pct_int}%${RESET}"

if [ "$LINES_ADD" -gt 0 ] 2>/dev/null || [ "$LINES_DEL" -gt 0 ] 2>/dev/null; then
  line1+="${SEP}✏️  ${GREEN}+${LINES_ADD}/-${LINES_DEL}${RESET}"
fi

if [ -n "$GIT_BRANCH" ]; then
  line1+="${SEP}🔀 ${GIT_BRANCH}"
fi

# ── Line 2: 5h rate limit ──
if [ -n "$FIVE_HR_PCT" ]; then
  c5=$(color_for_pct "$FIVE_HR_PCT")
  bar5=$(progress_bar "$FIVE_HR_PCT")
  line2="${c5}⏱ 5h  ${bar5}  ${FIVE_HR_PCT}%${RESET}"
  [ -n "$five_reset_display" ] && line2+="  ${DIM}${five_reset_display}${RESET}"
else
  line2="${GRAY}⏱ 5h  ▱▱▱▱▱▱▱▱▱▱  --%${RESET}"
fi

# ── Line 3: 7d rate limit ──
if [ -n "$SEVEN_DAY_PCT" ]; then
  c7=$(color_for_pct "$SEVEN_DAY_PCT")
  bar7=$(progress_bar "$SEVEN_DAY_PCT")
  line3="${c7}📅 7d  ${bar7}  ${SEVEN_DAY_PCT}%${RESET}"
  [ -n "$seven_reset_display" ] && line3+="  ${DIM}${seven_reset_display}${RESET}"
else
  line3="${GRAY}📅 7d  ▱▱▱▱▱▱▱▱▱▱  --%${RESET}"
fi

# ── Output ──
printf '%s\n' "$line1"
printf '%s\n' "$line2"
printf '%s' "$line3"
