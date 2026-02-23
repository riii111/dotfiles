---
description: CoVe loop : branch -> Plan Mode -> write plan -> user approval -> hand off to /plan-cove-exec
argument-hint: "branch=<name> | optional extra constraints/instructions (free-form)"
---

## HARD GATES (READ FIRST)
- Do NOT implement in this skill. Implementation is handled by `/plan-cove-exec`.
- If any required tool/agent cannot be invoked, STOP and **use `AskUserQuestion` tool**.
- If you are not in the next state, STOP and **use `AskUserQuestion` tool**.
- Plan must include explicit Phase 1/2/3 (or more) with commit boundaries before implementation.

## Input
$ARGUMENTS

---

# Step 0 — Pre-flight
1. Run `pwd` to confirm repo root
2. Run `git status --porcelain` to check if working tree is clean
3. If not clean: STOP and **use `AskUserQuestion` tool** to ask what to do

---

# Step 1 — Branch
- If `branch=<name>` is provided, use it
- Else: derive a short branch name and **use `AskUserQuestion` tool** to confirm

Run: `git checkout -b "<BRANCH_NAME>" && mkdir -p .claude/plans/<BRANCH_NAME>`

Plan and research files for this session:
- `.claude/plans/<BRANCH_NAME>/plan.md`
- `.claude/plans/<BRANCH_NAME>/research.md`

---

# Step 2 — Plan Mode
Enter Plan Mode (`EnterPlanMode` tool) and write your implementation plan in Japanese.

Collect the information you need:
- relevant modules / entry points
- data & API surface impacted
- constraints (perf/compat/security)
- risks and rollout/rollback needs

Hard rule:
- If anything changes the implementation shape (API/schema/compat/consistency/rollout),
  **STOP and use `AskUserQuestion` tool** with a crisp question (do NOT assume).

When the plan is complete, exit Plan Mode (`ExitPlanMode` tool) to get user approval.

After approval: instruct user to run `/plan-cove-exec branch=<BRANCH_NAME>` to continue.
