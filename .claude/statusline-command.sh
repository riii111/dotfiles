#!/usr/bin/env bash
# Claude Code statusline script
# Line 1: model | lines changed | branch | cost
# Line 2: context / rate-limit bars with gradient + reset time

# ── Colors ──
GREEN=$'\e[38;2;151;201;195m'
GRAY=$'\e[38;2;74;88;92m'
DIM=$'\e[2m'
RESET=$'\e[0m'
BLOCK_CHARS=(' ' '▏' '▎' '▍' '▌' '▋' '▊' '▉' '█')

# ── Read stdin JSON ──
INPUT=$(cat)
NOW_EPOCH=$(date +%s)

IFS=$'\t' read -r MODEL_DISPLAY CTX_PCT LINES_ADD LINES_DEL CWD COST_USD \
  WT_NAME WT_ORIG_BRANCH \
  FIVE_PCT FIVE_RESET_EPOCH WEEK_PCT WEEK_RESET_EPOCH < <(
  printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // "Unknown"),
    (.context_window.used_percentage // 0 | tostring),
    (.cost.total_lines_added // 0 | tostring),
    (.cost.total_lines_removed // 0 | tostring),
    (.cwd // "N/A"),
    (.cost.total_cost_usd // 0 | tostring),
    (.worktree.name // "N/A"),
    (.worktree.original_branch // "N/A"),
    (.rate_limits.five_hour.used_percentage // -1 | tostring),
    ((.rate_limits.five_hour.resets_at // null) | if . then (try (if type == "number" then . elif type == "string" then (gsub("\\.[0-9]+"; "") | gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601) else -1 end) catch -1) else -1 end | tostring),
    (.rate_limits.seven_day.used_percentage // -1 | tostring),
    ((.rate_limits.seven_day.resets_at // null) | if . then (try (if type == "number" then . elif type == "string" then (gsub("\\.[0-9]+"; "") | gsub("[+-][0-9]{2}:[0-9]{2}$"; "Z") | fromdateiso8601) else -1 end) catch -1) else -1 end | tostring)
  ] | @tsv' 2>/dev/null
)

# ── Helpers ──
is_number() {
  printf '%s' "$1" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'
}

gradient_color() {
  local ipct=0
  is_number "$1" && ipct=$(printf "%.0f" "$1" 2>/dev/null || echo 0)
  [ "$ipct" -lt 0 ] && ipct=0
  [ "$ipct" -gt 100 ] && ipct=100
  if [ "$ipct" -lt 50 ]; then
    printf '\e[38;2;%d;200;80m' "$(( ipct * 255 / 50 ))"
  else
    local g=$(( 200 - (ipct - 50) * 4 ))
    [ "$g" -lt 0 ] && g=0
    printf '\e[38;2;255;%d;60m' "$g"
  fi
}

render_bar() {
  local ipct=0 width="${2:-10}"
  is_number "$1" && ipct=$(printf "%.0f" "$1" 2>/dev/null || echo 0)
  [ "$ipct" -lt 0 ] && ipct=0
  [ "$ipct" -gt 100 ] && ipct=100
  local filled_x100=$(( ipct * width ))
  local full=$(( filled_x100 / 100 ))
  local frac=$(( (filled_x100 - full * 100) * 8 / 100 ))
  local bar="" i=0
  while [ "$i" -lt "$full" ]; do bar+="${BLOCK_CHARS[8]}"; i=$(( i + 1 )); done
  if [ "$full" -lt "$width" ]; then
    if [ "$frac" -gt 0 ]; then
      bar+="${BLOCK_CHARS[$frac]}"
      i=$(( width - full - 1 ))
    else
      i=$(( width - full ))
    fi
    while [ "$i" -gt 0 ]; do bar+=$'\xe2\x96\x91'; i=$(( i - 1 )); done
  fi
  printf '%s' "$bar"
}

time_until_epoch() {
  local reset_epoch="$1"
  is_number "$reset_epoch" || return 1
  [ "$reset_epoch" -le 0 ] && return 1
  local diff=$(( reset_epoch - NOW_EPOCH ))
  [ "$diff" -le 0 ] && { printf 'now'; return 0; }
  local h=$(( diff / 3600 )) m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then
    printf '%dh%02dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

fmt_bar() {
  local label="$1" pct="$2" reset_epoch="$3"
  local ipct=0
  is_number "$pct" && ipct=$(printf "%.0f" "$pct" 2>/dev/null || echo 0)
  local color bar
  color=$(gradient_color "$pct")
  bar=$(render_bar "$pct" 10)
  printf '%s %s%b %d%%' "$label" "$color" "$bar" "$ipct"
  local remain
  if remain=$(time_until_epoch "$reset_epoch"); then
    printf ' (%s)' "$remain"
  fi
  printf '%s' "$RESET"
}

fmt_bar_na() {
  local label="$1"
  printf '%s %s---%s' "$label" "$DIM" "$RESET"
}

SEP="${GRAY} │ ${RESET}"

# ════════════════════════════════════════════════════════════
# Line 1: model | lines | branch | cost
# ════════════════════════════════════════════════════════════
build_line1() {
  local out="🤖 ${MODEL_DISPLAY}"

  if [ "$LINES_ADD" -gt 0 ] 2>/dev/null || [ "$LINES_DEL" -gt 0 ] 2>/dev/null; then
    out+="${SEP}✏️  ${GREEN}+${LINES_ADD}/-${LINES_DEL}${RESET}"
  fi

  if [ "$WT_NAME" != "N/A" ] && [ -n "$WT_NAME" ]; then
    out+="${SEP}🌳 ${WT_NAME}"
    [ "$WT_ORIG_BRANCH" != "N/A" ] && [ -n "$WT_ORIG_BRANCH" ] && out+=" ← ${WT_ORIG_BRANCH}"
  elif [ -n "$GIT_BRANCH" ]; then
    out+="${SEP}🔀 ${GIT_BRANCH}"
  fi

  if is_number "$COST_USD" && [ "$(awk "BEGIN{print ($COST_USD > 0)}")" = "1" ]; then
    out+="${SEP}💰 $(awk "BEGIN{printf \"$%.2f\", $COST_USD}")"
  fi

  printf '%s' "$out"
}

# ════════════════════════════════════════════════════════════
# Line 2: usage bars (ctx / 5h / 7d) — always show all slots
# ════════════════════════════════════════════════════════════
build_line2() {
  local parts=() ctx_pct=0

  # ctx: always available
  is_number "$CTX_PCT" && ctx_pct=$(printf "%.0f" "$CTX_PCT" 2>/dev/null || echo 0)
  parts+=("$(fmt_bar "ctx" "$ctx_pct" "-1")")

  # 5h rate limit
  if is_number "$FIVE_PCT" && [ "$(awk "BEGIN{print ($FIVE_PCT >= 0)}")" = "1" ]; then
    local five_int
    five_int=$(printf "%.0f" "$FIVE_PCT" 2>/dev/null || echo 0)
    parts+=("$(fmt_bar "5h" "$five_int" "$FIVE_RESET_EPOCH")")
  else
    parts+=("$(fmt_bar_na "5h")")
  fi

  # 7d rate limit
  if is_number "$WEEK_PCT" && [ "$(awk "BEGIN{print ($WEEK_PCT >= 0)}")" = "1" ]; then
    local week_int
    week_int=$(printf "%.0f" "$WEEK_PCT" 2>/dev/null || echo 0)
    parts+=("$(fmt_bar "7d" "$week_int" "$WEEK_RESET_EPOCH")")
  else
    parts+=("$(fmt_bar_na "7d")")
  fi

  local out=""
  for i in "${!parts[@]}"; do
    [ "$i" -gt 0 ] && out+="${SEP}"
    out+="${parts[$i]}"
  done
  printf '%s' "$out"
}

# ── Git branch ──
GIT_BRANCH=""
if [ "$CWD" != "N/A" ] && [ -n "$CWD" ] && [ -d "$CWD" ]; then
  GIT_BRANCH=$(git -C "$CWD" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
fi

# ── Output ──
printf '%s\n%s' "$(build_line1)" "$(build_line2)"
