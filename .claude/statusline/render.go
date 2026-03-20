package main

import (
	"fmt"
	"math"
	"strings"
	"time"
)

// ════════════════════════════════════════════════════════════
// Line builders (top-level public API)
// ════════════════════════════════════════════════════════════

// BuildLine1 renders: model | ctx% | lines changed | branch | cost
func BuildLine1(in Input, gitBranch string) string {
	out := "🤖 " + in.Model.DisplayName

	ctxPct := clamp(in.ContextWindow.UsedPercentage)
	out += sep + fmt.Sprintf("📊 %s%d%%%s", gradientColor(ctxPct), ctxPct, reset)

	if in.Cost.TotalLinesAdded > 0 || in.Cost.TotalLinesRemoved > 0 {
		out += sep + fmt.Sprintf("✏️  %s+%d/-%d%s", green, in.Cost.TotalLinesAdded, in.Cost.TotalLinesRemoved, reset)
	}

	switch {
	case in.Worktree.Name != "":
		out += sep + "🌳 " + in.Worktree.Name
		if in.Worktree.OriginalBranch != "" {
			out += " ← " + in.Worktree.OriginalBranch
		}
	case gitBranch != "":
		out += sep + "🔀 " + gitBranch
	}

	if in.Cost.TotalCostUSD > 0 {
		out += sep + fmt.Sprintf("💰 $%.2f", in.Cost.TotalCostUSD)
	}

	return out
}

// BuildLine2 renders: 5h / 7d rate-limit bars
func BuildLine2(in Input, now time.Time) string {
	parts := []string{
		formatRateLimit("5h", in.RateLimits.FiveHour, now),
		formatRateLimit("7d", in.RateLimits.SevenDay, now),
	}
	return strings.Join(parts, sep)
}

// ════════════════════════════════════════════════════════════
// Bar rendering
// ════════════════════════════════════════════════════════════

var blockChars = [9]rune{' ', '▏', '▎', '▍', '▌', '▋', '▊', '▉', '█'}

func renderBar(pct, width int) string {
	pct = max(0, min(100, pct))
	filledX100 := pct * width
	full := filledX100 / 100
	frac := (filledX100 - full*100) * 8 / 100

	var b strings.Builder
	for range full {
		b.WriteRune(blockChars[8])
	}
	if full < width {
		empty := width - full
		if frac > 0 {
			b.WriteRune(blockChars[frac])
			empty--
		}
		for range empty {
			b.WriteRune('░')
		}
	}
	return b.String()
}

func formatBar(label string, pct int, rt ResetTime, now time.Time) string {
	color := gradientColor(pct)
	bar := renderBar(pct, 10)
	s := fmt.Sprintf("%s %s%s %d%%", label, color, bar, pct)
	if rt.Valid {
		s += " (" + timeUntil(rt.Time, now) + ")"
	}
	return s + reset
}

func formatRateLimit(label string, rl RateLimit, now time.Time) string {
	if rl.UsedPercentage == nil || *rl.UsedPercentage < 0 {
		return fmt.Sprintf("%s %s---%s", label, dim, reset)
	}
	return formatBar(label, clamp(*rl.UsedPercentage), rl.ResetsAt, now)
}

// ════════════════════════════════════════════════════════════
// ANSI colors
// ════════════════════════════════════════════════════════════

const (
	green = "\033[38;2;151;201;195m"
	gray  = "\033[38;2;74;88;92m"
	dim   = "\033[2m"
	reset = "\033[0m"
)

var sep = gray + " │ " + reset

// gradientColor returns green→yellow→red ANSI escape for 0–100%
func gradientColor(pct int) string {
	pct = max(0, min(100, pct))
	if pct < 50 {
		return fmt.Sprintf("\033[38;2;%d;200;80m", pct*255/50)
	}
	return fmt.Sprintf("\033[38;2;255;%d;60m", max(0, 200-(pct-50)*4))
}

// ════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════

func clamp(f float64) int {
	v := int(math.Round(f))
	return max(0, min(100, v))
}

func timeUntil(target, now time.Time) string {
	d := target.Sub(now)
	if d <= 0 {
		return "now"
	}
	h, m := int(d.Hours()), int(d.Minutes())%60
	if h > 0 {
		return fmt.Sprintf("%dh%02dm", h, m)
	}
	return fmt.Sprintf("%dm", m)
}
