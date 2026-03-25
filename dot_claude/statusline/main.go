package main

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// ════════════════════════════════════════════════════════════
// Entry point
// ════════════════════════════════════════════════════════════

func main() {
	input, err := ParseInput(os.Stdin)
	if err != nil {
		fmt.Fprintf(os.Stdout, "🤖 Unknown\n%s---%s", dim, reset)
		return
	}

	branch := DetectBranch(input.CWD)
	width := TermWidth()

	fmt.Fprintln(os.Stdout, BuildStatusLine(input, branch, width))
}

// ════════════════════════════════════════════════════════════
// JSON Model
// ════════════════════════════════════════════════════════════

type Input struct {
	Model struct {
		DisplayName string `json:"display_name"`
	} `json:"model"`
	ContextWindow struct {
		UsedPercentage float64 `json:"used_percentage"`
	} `json:"context_window"`
	Cost struct {
		TotalLinesAdded   int     `json:"total_lines_added"`
		TotalLinesRemoved int     `json:"total_lines_removed"`
		TotalCostUSD      float64 `json:"total_cost_usd"`
	} `json:"cost"`
	CWD      string `json:"cwd"`
	Worktree struct {
		Name           string `json:"name"`
		OriginalBranch string `json:"original_branch"`
	} `json:"worktree"`
	RateLimits struct {
		FiveHour RateLimit `json:"five_hour"`
		SevenDay RateLimit `json:"seven_day"`
	} `json:"rate_limits"`
}

type RateLimit struct {
	UsedPercentage *float64  `json:"used_percentage"`
	ResetsAt       ResetTime `json:"resets_at"`
}

func ParseInput(r io.Reader) (Input, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return Input{}, err
	}
	var in Input
	if err := json.Unmarshal(data, &in); err != nil {
		return Input{}, err
	}
	if in.Model.DisplayName == "" {
		in.Model.DisplayName = "Unknown"
	}
	return in, nil
}

// ── ResetTime: epoch number or ISO 8601 string ──

type ResetTime struct {
	Time  time.Time
	Valid bool
}

func (rt *ResetTime) UnmarshalJSON(data []byte) error {
	var raw any
	if json.Unmarshal(data, &raw) != nil {
		return nil
	}
	switch v := raw.(type) {
	case float64:
		if v > 0 {
			sec, frac := math.Modf(v)
			rt.Time = time.Unix(int64(sec), int64(frac*1e9))
			rt.Valid = true
		}
	case string:
		for _, layout := range []string{time.RFC3339Nano, time.RFC3339, "2006-01-02T15:04:05Z", "2006-01-02T15:04:05"} {
			if t, err := time.Parse(layout, v); err == nil {
				rt.Time, rt.Valid = t, true
				return nil
			}
		}
		if epoch, err := strconv.ParseFloat(v, 64); err == nil && epoch > 0 {
			sec, frac := math.Modf(epoch)
			rt.Time = time.Unix(int64(sec), int64(frac*1e9))
			rt.Valid = true
		}
	}
	return nil
}

// ════════════════════════════════════════════════════════════
// Git
// ════════════════════════════════════════════════════════════

func DetectBranch(cwd string) string {
	if cwd == "" {
		return ""
	}
	out, err := exec.Command("git", "-C", cwd, "--no-optional-locks", "rev-parse", "--abbrev-ref", "HEAD").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
