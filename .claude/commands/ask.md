---
description: Interview-mode feasibility check (runs in a forked sub-agent context)
argument-hint: "Paste the proposal + current context (goal, constraints, relevant snippets/links). 5-30 lines."
context: fork
agent: Explore
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(rg:*), Bash(ls:*), Bash(cat:*)
---

## Input (shared by the caller; treat it as authoritative)

$ARGUMENTS

## Task (Ask-mode, feasibility-focused)

You are running as a forked sub-agent. Your job is to **surface hidden assumptions, constraints, and feasibility blockers**
BEFORE we write an ADR/spec or implement anything.

### Hard rules
- Do NOT design the full solution.
- Do NOT request broad context (assume the caller already pasted what matters).
- Ask only questions that, if unanswered, would cause wrong design decisions or rework.
- Max **7 questions**.

### Output format (strict)

For each question:
1) **Question** (prefer Yes/No or a short factual answer)
2) **Why it matters** (1 line)
3) **Default assumption if unanswered** (1 line)

### Question priorities (in this order)
1) Goal & success criteria (what “good” means)
2) Scope boundaries (in / out)
3) Constraints (latency, cost, compliance, SLOs)
4) Data & correctness (idempotency, ordering, consistency, migrations)
5) Integrations & compatibility (contracts, versioning, clients)
6) Operations (observability, rollback/kill-switch)
7) Effort / timeline (only if it affects feasibility)

### After the questions: produce a short "Decision Draft"
Even before answers:
- **Feasibility**: Yes / Maybe / No
- **Top 2 options** (1–2 lines each)
- **Top risks** (max 5 bullets)
- **Next step** (max 3 bullets)

Keep it crisp and practical.
