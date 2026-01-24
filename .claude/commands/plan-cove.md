---
description: CoVe loop : branch -> Plan Mode -> write EN plan -> codex 2nd review -> reflect -> implement (commit per phase)
argument-hint: "branch=<name> | optional extra constraints/instructions (free-form)"
---

## HARD GATES (READ FIRST)
- Do NOT implement until: plan drafted -> user approved -> codex review done -> plan updated -> user re-approved.
- After each phase commit, STOP and ask the user to continue.
- If any required tool/agent cannot be invoked, STOP and **use `AskUserQuestion` tool**.
- If you are not in the next state, STOP and **use `AskUserQuestion` tool**.
- Plan must include explicit Phase 1/2/3 (or more) with commit boundaries before implementation.

## STATE TRANSITIONS (MUST FOLLOW)
- Draft Plan -> User Approval -> Codex Review -> Plan Updated -> User Re-Approval -> Implement Phase N -> Commit -> Ask to Continue

## Input 
$ARGUMENTS

## What this command does
A fast CoVe-style loop:
- Create a branch
- Enter Plan Mode to gather info and write a plan (in English)
- If a decision is ambiguous, ask the user immediately (do not guess)
- Ask "codex 2nd agent" to review the plan
- Apply feedback to the plan
- Implement phase-by-phase

---

# Step 0 — Pre-flight
1. Run `pwd` to confirm repo root
2. Run `git status --porcelain` to check if working tree is clean
3. If not clean: STOP and **use `AskUserQuestion` tool** to ask what to do

---

# Step 1 — Branch
- If `branch=<name>` is provided, use it
- Else: derive a short branch name and **use `AskUserQuestion` tool** to confirm

Run: `git checkout -b "<BRANCH_NAME>"`

---

# Step 2 — Plan Mode
Enter Plan Mode (`EnterPlanMode` tool) and write your implementation plan in English.

Collect the information you need:
- relevant modules / entry points
- data & API surface impacted
- constraints (perf/compat/security)
- risks and rollout/rollback needs

Hard rule:
- If anything changes the implementation shape (API/schema/compat/consistency/rollout),
  **STOP and use `AskUserQuestion` tool** with a crisp question (do NOT assume).

When the plan is complete, exit Plan Mode (`ExitPlanMode` tool) to get user approval.

---

# Step 3 — Ask "codex 2nd agent" to review the plan
Invoke your configured "codex 2nd agent" using your local convention.

Send the plan content with this prompt:

"Review this plan as a senior engineer. Find missing assumptions, edge cases, and rollout/rollback gaps.
Output:
- P0 (must fix before implementation)
- P1 (nice-to-have)
- Any missing tests
Keep it concise."

---
 
# Step 4 — Reflect codex feedback into the plan
Update the plan based on feedback.

If codex feedback introduces a new ambiguity:
- STOP and **use `AskUserQuestion` tool** before coding.

If codex feedback changes scope/spec or requires a trade-off decision, STOP and **use `AskUserQuestion` tool** before applying it.

---

# Step 5 — Implement phase-by-phase
For each phase:
- implement tasks
- run checks/tests
- commit (title only, no body)

If you discover plan-level changes, update the plan first.
