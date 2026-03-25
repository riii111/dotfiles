package main

import (
	"fmt"
	"math"
	"os"
	"strconv"
	"strings"
	"unicode"

	"golang.org/x/sys/unix"
)

// ════════════════════════════════════════════════════════════
// Line builders (top-level public API)
// ════════════════════════════════════════════════════════════

// BuildStatusLine renders a single-line statusline.
// Segments in priority order; low-priority ones are dropped when narrow.
func BuildStatusLine(in Input, gitBranch string, maxWidth int) string {
	var segs []string

	segs = append(segs, "🤖 "+in.Model.DisplayName)

	ctxPct := clamp(in.ContextWindow.UsedPercentage)
	segs = append(segs, fmt.Sprintf("📊 %s%d%%%s", thresholdColor(ctxPct), ctxPct, reset))

	segs = append(segs, formatRingRateLimits(in.RateLimits))

	switch {
	case in.Worktree.Name != "":
		wt := "🌳 " + in.Worktree.Name
		if in.Worktree.OriginalBranch != "" {
			wt += " ← " + in.Worktree.OriginalBranch
		}
		segs = append(segs, wt)
	case gitBranch != "":
		segs = append(segs, "🔀 "+gitBranch)
	}

	if in.Cost.TotalLinesAdded > 0 || in.Cost.TotalLinesRemoved > 0 {
		segs = append(segs, fmt.Sprintf("%s+%d/-%d%s", green, in.Cost.TotalLinesAdded, in.Cost.TotalLinesRemoved, reset))
	}

	return joinSegments(segs, maxWidth)
}

// ════════════════════════════════════════════════════════════
// Ring Meter rendering
// ════════════════════════════════════════════════════════════

// ringChars maps usage percentage to a pie-segment circle.
// ○ = 0%, ◔ = ~25%, ◑ = ~50%, ◕ = ~75%, ● = ~100%
var ringChars = [5]rune{'○', '◔', '◑', '◕', '●'}

func ringChar(pct int) rune {
	idx := (pct + 12) / 25 // 0-12→0, 13-37→1, 38-62→2, 63-87→3, 88-100→4
	return ringChars[min(idx, 4)]
}

func formatRingRate(label string, rl RateLimit) string {
	if rl.UsedPercentage == nil || *rl.UsedPercentage < 0 {
		return fmt.Sprintf("%s%s-%s", label, dim, reset)
	}
	pct := clamp(*rl.UsedPercentage)
	color := thresholdColor(pct)
	return fmt.Sprintf("%s%s%c%d%%%s", label, color, ringChar(pct), pct, reset)
}

// formatRingRateLimits renders "5h◔30% 7d◑15%" as a single compact segment.
func formatRingRateLimits(rl struct {
	FiveHour RateLimit `json:"five_hour"`
	SevenDay RateLimit `json:"seven_day"`
}) string {
	return formatRingRate("5h", rl.FiveHour) + " " + formatRingRate("7d", rl.SevenDay)
}

// ════════════════════════════════════════════════════════════
// ANSI colors
// ════════════════════════════════════════════════════════════

const (
	green  = "\033[38;2;151;201;195m" // #97C9C3
	yellow = "\033[38;2;229;192;123m" // #E5C07B
	red    = "\033[38;2;224;108;117m" // #E06C75
	gray   = "\033[38;2;74;88;92m"    // #4A585C
	dim    = "\033[2m"
	reset  = "\033[0m"
)

var sep = gray + " │ " + reset

// thresholdColor returns green/yellow/red based on usage percentage
func thresholdColor(pct int) string {
	switch {
	case pct >= 80:
		return red
	case pct >= 50:
		return yellow
	default:
		return green
	}
}

// ════════════════════════════════════════════════════════════
// Terminal width
// ════════════════════════════════════════════════════════════

func TermWidth() int {
	if s, ok := os.LookupEnv("COLUMNS"); ok {
		if v, err := strconv.Atoi(s); err == nil && v > 0 {
			return v
		}
	}
	if ws, err := unix.IoctlGetWinsize(int(os.Stdout.Fd()), unix.TIOCGWINSZ); err == nil && ws.Col > 0 {
		return int(ws.Col)
	}
	return 0 // unknown — no truncation
}

// ════════════════════════════════════════════════════════════
// Visible width (ANSI-stripped, East Asian Width aware)
// ════════════════════════════════════════════════════════════

func visibleWidth(s string) int {
	w := 0
	for _, r := range stripANSI(s) {
		w += runeWidth(r)
	}
	return w
}

func stripANSI(s string) string {
	var b strings.Builder
	inEsc := false
	for _, r := range s {
		if inEsc {
			if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') {
				inEsc = false
			}
			continue
		}
		if r == '\033' {
			inEsc = true
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}

func runeWidth(r rune) int {
	if r < 0x20 {
		return 0
	}
	// Emoji: most common ranges
	if r >= 0x1F300 && r <= 0x1FAFF {
		return 2
	}
	// Variation selectors / ZWJ
	if r == 0xFE0F || r == 0x200D {
		return 0
	}
	// CJK / fullwidth
	if unicode.Is(unicode.Han, r) || unicode.Is(unicode.Hangul, r) || unicode.Is(unicode.Katakana, r) || unicode.Is(unicode.Hiragana, r) {
		return 2
	}
	// Unicode East Asian Fullwidth/Wide block indicators
	if (r >= 0xFF01 && r <= 0xFF60) || (r >= 0xFFE0 && r <= 0xFFE6) {
		return 2
	}
	return 1
}

// ════════════════════════════════════════════════════════════
// Segment joining with width budget
// ════════════════════════════════════════════════════════════

const sepWidth = 3 // " │ "

func joinSegments(segments []string, maxWidth int) string {
	if maxWidth <= 0 {
		return strings.Join(segments, sep)
	}
	var kept []string
	used := 0
	for _, s := range segments {
		w := visibleWidth(s)
		need := w
		if len(kept) > 0 {
			need += sepWidth
		}
		if used+need > maxWidth {
			break
		}
		kept = append(kept, s)
		used += need
	}
	if len(kept) == 0 && len(segments) > 0 {
		kept = segments[:1] // always show at least model
	}
	return strings.Join(kept, sep)
}

// ════════════════════════════════════════════════════════════
// Helpers
// ════════════════════════════════════════════════════════════

func clamp(f float64) int {
	v := int(math.Round(f))
	return max(0, min(100, v))
}

