---
description: CoVe loop : branch -> Plan Mode -> write EN plan -> codex 2nd review -> reflect -> implement (commit per phase)
argument-hint: "branch=<name> | optional extra constraints/instructions (free-form)"
---

## Input 
$ARGUMENTS

## What this command does
A fast CoVe-style loop:
- Create a branch
- Enter Plan Mode to gather info 
- If a decision is ambiguous, ask the user immediately (do not guess)
- Write a short English plan file (as a memory anchor)
- Ask "codex 2nd agent" to review the plan
- Apply feedback to the plan
- Implement phase-by-phase

> IMPORTANT:
> - **Commit at the end of EACH phase** (title only, no body).
> - Plan Mode may clear/compact context; the plan file should capture the essentials.

---

# Step 0 — Pre-flight
- repo root: !`pwd`
- working tree clean? !`git status --porcelain`
- If not clean: STOP and ask the user what to do.

---

# Step 1 — Branch
- If `branch=<name>` is provided, use it.
- Else: derive a short branch name and ask the user to confirm.

Command:
- !`git checkout -b "<BRANCH_NAME>"`

---

# Step 2 — Plan Mode 
Switch to Plan Mode and collect only the information you need:
- relevant modules / entry points
- data & API surface impacted
- constraints (perf/compat/security)
- risks and rollout/rollback needs

Hard rule:
- If anything changes the implementation shape (API/schema/compat/consistency/rollout),
  **STOP and ask the user a crisp question** (do NOT assume).

---

# Step 3 — Write a plan file
- !`mkdir -p .claude/plans`
- !`date +%Y%m%d`

Write it:
- !`tee .claude/plans/<PLAN_FILE>.md >/dev/null << 'EOF'
# Plan: <Short Title>

## Goal
- What we want:
- Success criteria:

## Non-goals
- Out of scope:

## Key decisions / assumptions
- Decision:
- Assumption:
- Unknowns (must confirm before coding):

## Approach (2–6 bullets)
- Default approach:
- Fallback option (if needed):

## Risks / Rollback (short)
- Risk:
- How we detect it:
- Rollback / kill-switch:

## Phases (commit at end of each phase)
> RULE: **Commit at the end of EACH phase (title only, no body).**

### Phase 1 — <title>
- Tasks:
  - [ ] ...
- Done when:
- Commit title: `phase1: <short>`

### Phase 2 — <title>
- Tasks:
  - [ ] ...
- Done when:
- Commit title: `phase2: <short>`

### Phase 3 — <title>
- Tasks:
  - [ ] ...
- Done when:
- Commit title: `phase3: <short>`
EOF`

---

# Step 4 — Ask "codex 2nd agent" to review the plan
Invoke your configured "codex 2nd agent" using your local convention.

Send:
1) the plan file content
2) this prompt:

"Review this plan as a senior engineer. Find missing assumptions, edge cases, and rollout/rollback gaps.
Output:
- P0 (must fix before implementation)
- P1 (nice-to-have)
- Any missing tests
Keep it concise."

---

# Step 5 — Reflect codex feedback into the plan
Update:
- Key decisions/assumptions
- Risks/Rollback
- Phases (tasks & done-criteria)

If codex feedback introduces a new ambiguity:
- STOP and ask the user before coding.

If codex feedback changes scope/spec or requires a trade-off decision, STOP and ask the user before applying it.

---

# Step 6 — Implement phase-by-phase
For each phase:
- implement tasks
- run checks/tests relevant to the phase
- **commit at end of the phase** (title only, no body)

If you discover plan-level changes:
- update the plan file first, then continue.
