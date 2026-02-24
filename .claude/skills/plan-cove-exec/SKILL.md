---
description: Execution phase of CoVe loop. Run after plan-cove completes.
argument-hint: "branch=<name>"
---

## PRECONDITION
- Plan Mode is **already active** (inherited from plan-cove). Do NOT call `EnterPlanMode`.
- Plan file: `.claude/plans/<BRANCH_NAME>/plan.md`

---

# Step 1 — User Annotation Cycle (Plan Mode, 1–6 rounds typical)

This is the most important step. Inspired by Boris Tane's annotation workflow:
the plan improves through repeated inline review, not one-shot approval.

**Use `AskUserQuestion` tool**:
"Annotation round. Review `.claude/plans/<BRANCH_NAME>/plan.md` and add inline notes, or type `done` to finish annotation and proceed to Codex review."

If user provides annotations:
- Re-read `.claude/plans/<BRANCH_NAME>/plan.md`
- Incorporate all inline notes:
  - Wrong assumption → correct (e.g. "no — this API already exists")
  - Rejected approach → remove or replace (e.g. "remove this section")
  - Domain constraint → integrate (e.g. "RLS required on this table")
- After incorporating, **loop back to the top of Step 1** for another round
- Typical projects need 1–6 rounds — keep cycling until the user says `done`

If `done`: proceed to Step 2.

---

# Step 2 — Codex Review (HARD GATE — DO NOT SKIP)

Run exactly:
```bash
codex "Review this plan as a senior engineer. Find missing assumptions, edge cases, and rollout/rollback gaps.
Output:
- P0 (must fix before implementation)
- P1 (nice-to-have)
- Any missing tests
Keep it concise.

$(cat .claude/plans/<BRANCH_NAME>/plan.md)"
```

After running, STOP and **use `AskUserQuestion` tool**:
"Codex review complete. P0 issues found: [list or none]. Proceed to Step 3?"

If codex CLI is unavailable: STOP immediately and **use `AskUserQuestion` tool**.

---

# Step 3 — Reflect codex feedback into the plan
Update the plan based on feedback.

If codex feedback introduces a new ambiguity:
- STOP and **use `AskUserQuestion` tool** before coding.

If codex feedback changes scope/spec or requires a trade-off decision, STOP and **use `AskUserQuestion` tool** before applying it.

---

# Step 4 — Exit Plan Mode & Implement phase-by-phase

Call `ExitPlanMode` to leave Plan Mode and begin implementation.

For each phase:
- implement tasks
- run checks/tests
- commit (title only, no body)

If you discover plan-level changes, update the plan first.

