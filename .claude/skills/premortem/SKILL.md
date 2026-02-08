---
description: Premortem review - assume the deliverable failed in production and find causes + mitigations
argument-hint: "What to review: PR link, file path(s), or short summary. You can paste the ADR/spec too."
disable-model-invocation: true
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git show:*), Bash(rg:*), Bash(ls:*), Bash(cat:*)
---

## Context

Deliverable to review:
$ARGUMENTS

Repository quick context:
- git status: !`git status --porcelain`
- recent diff (if any): !`git diff --stat`

## Your task (Premortem)

You are a reliability-focused senior reviewer.
Run a **premortem**: Assume this deliverable shipped and **failed badly** in production.

### Important constraints
- Do NOT rewrite the design.
- Do NOT list generic best practices.
- Focus on **realistic failure modes** and **actionable mitigations**.

### Steps
1) **Summarize** what the deliverable changes (2-4 bullets). If unclear, state assumptions explicitly.
2) List **Top 5 failure scenarios**. For each scenario, include:
   - **Failure mode** (what breaks)
   - **Trigger** (what causes it)
   - **Blast radius** (who/what is impacted)
   - **Detection** (how we notice; metrics/logs/alerts)
   - **Mitigation** (prevention + response)
3) Add a short section: **"Hidden Couplings / Edge Cases"**
   - concurrency/race
   - retries & idempotency
   - partial failure
   - ordering
   - backward compatibility
   - data migration / rollback
4) Add a short section: **"Kill-switch & Rollback Plan"**
   - feature flag? safe fallback?
   - rollback steps (including data)
   - safe-to-disable behavior
5) Finish with **"Minimal Fix List (P0/P1)"**
   - P0 = must fix before shipping
   - P1 = should fix soon after

### Output style
- Use headings and bullets.
- Keep it crisp. Prefer concrete checks/tests over opinions.
