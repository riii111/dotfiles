---
description: |
  Review an implemented change for correctness, consistency, and pragmatic quality.
  Use a small review team only when clearly beneficial.
argument-hint: "[-sec] [-lite]"
---

# code-review

Do review only.

## Args
- -sec: add security-reviewer (for auth/input/secrets/network sensitive work)
- -lite: blocking-focused output, short

Review team size is auto-selected based on change scope.

## Review team (auto-selected)

### solo (single-agent review)
When: change is small, no new abstraction, no sensitive area, little risk of codebase inconsistency.

Covers both correctness and consistency perspectives.

### team (code-reviewer + consistency-reviewer)
When: multiple modules/layers changed, new abstraction or API shape introduced, broader consistency issues are plausible, code works but may not fit the repo cleanly.

#### code-reviewer focus
- correctness
- readability
- unnecessary branching/fallbacks
- test/validation gaps

#### consistency-reviewer focus
- naming consistency
- layering / responsibility fit
- duplication vs reuse
- whether the touched area now looks inconsistent with surrounding code
- whether a small local refactor would materially improve coherence

### +sec (added when -sec specified or sensitive surface detected)

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
