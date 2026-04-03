---
description: |
  Review an implemented change for correctness, consistency, and pragmatic quality.
  Team/sec subagents are mandatory when the selected review mode requires them.
argument-hint: "[-sec] [-lite]"
---

# code-review

Do review only.

## Args
- -sec: add security-reviewer (for auth/input/secrets/network sensitive work)
- -lite: blocking-focused output, short — skip Phase 0 and use Quick mode

## Phase 0: Confirm review mode

If -lite is set, skip this phase and use Quick mode.

Otherwise, ask the user:
1. **Review mode**: Quick / Standard / Deep
2. **Focus areas** (optional, free-form)

Mode mapping:
- **Quick** → solo review
- **Standard** → team review (code-reviewer + consistency-reviewer subagents)
- **Deep** → team review + security-reviewer subagent

If -sec flag was passed, add security-reviewer regardless of mode choice.

## Review team

### Quick (single-agent review)
No subagents. You perform the review yourself covering both correctness and consistency.

### Standard (code-reviewer + consistency-reviewer subagents)
Use when: multiple modules/layers changed, new abstraction or API shape introduced, broader consistency issues are plausible, code works but may not fit the repo cleanly.

#### code-reviewer focus
- correctness
- readability
- unnecessary branching/fallbacks
- fallback paths not justified by real failure modes
- defensive code that adds noise without meaningful risk reduction
- test/validation gaps

#### consistency-reviewer focus
- naming consistency
- layering / responsibility fit
- duplication vs reuse
- whether the touched area now looks inconsistent with surrounding code
- whether a small local refactor would materially improve coherence
- whether nearby code should be lightly aligned in the same change
- whether the implementation is locally convenient but globally off-pattern

### +sec (added in Deep mode, or when -sec specified)

#### security-reviewer focus
- auth/authz
- input validation
- secret/config handling
- unsafe file/network behavior

## Output format
Return:
- Blocking
- Non-blocking
- Consistency / refactor opportunities
- Fix now vs later

If -lite is set:
- return only Blocking
- then up to 3 high-value non-blocking comments

## Review style
Be pragmatic. Suggest only what is clearly worth doing now.
Distinguish "blocks this task" from "improves the codebase."
