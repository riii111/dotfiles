#!/usr/bin/env bash
# Claude Code statusline script
# Reads JSON from stdin, outputs single-line ANSI-colored status

# ── Colors ──
GREEN=$'\e[38;2;151;201;195m'
YELLOW=$'\e[38;2;229;192;123m'
RED=$'\e[38;2;224;108;117m'
GRAY=$'\e[38;2;74;88;92m'
RESET=$'\e[0m'

# ── Read stdin JSON (eval-free, @tsv) ──
INPUT=$(cat)
IFS=$'\t' read -r MODEL_DISPLAY CTX_PCT LINES_ADD LINES_DEL CWD COST_USD WT_NAME WT_ORIG_BRANCH < <(
  printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // "Unknown"),
    (.context_window.used_percentage // 0 | tostring),
    (.cost.total_lines_added // 0 | tostring),
    (.cost.total_lines_removed // 0 | tostring),
    (.cwd // ""),
    (.cost.total_cost_usd // 0 | tostring),
    (.worktree.name // ""),
    (.worktree.original_branch // "")
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

# ── Branch / Worktree ──
if [ -n "$WT_NAME" ]; then
  line1+="${SEP}🌳 ${WT_NAME}"
  [ -n "$WT_ORIG_BRANCH" ] && line1+=" ← ${WT_ORIG_BRANCH}"
elif [ -n "$GIT_BRANCH" ]; then
  line1+="${SEP}🔀 ${GIT_BRANCH}"
fi

# ── Cost ──
if is_number "$COST_USD" && [ "$(awk "BEGIN{print ($COST_USD > 0)}")" = "1" ]; then
  cost_display=$(awk "BEGIN{printf \"$%.2f\", $COST_USD}")
  line1+="${SEP}💰 ${cost_display}"
fi

# ── Output ──
printf '%s' "$line1"
