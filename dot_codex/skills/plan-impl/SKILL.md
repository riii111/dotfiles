---
description: |
  Plan and implement pragmatically.
  Ask only when ambiguity would materially change the implementation.
  Keep implementation in a single main thread.
  Use plan subagents only when clearly helpful.
argument-hint: "[-w] [-quick] [branch=<name>] [task description (free-form)]"
---

# plan-impl

Do plan -> implement.

## Args
- -w: create a git worktree for parallel development
- -quick: minimize questions and keep planning lightweight
- branch=<name>: specify branch name (otherwise auto-derived)

All other decisions (planning depth, subagent usage) are auto-selected based on task complexity.

## Phase 0: Workspace setup

1. Run `git status --porcelain` to check working tree is clean
2. If not clean: STOP and ask the user what to do

### Normal mode (default)
- If `branch=<name>` provided, use it; else derive a short name and confirm with user
- Run: `git checkout -b "<BRANCH_NAME>"`

### Worktree mode (-w)
- If `branch=<name>` provided, use it; else derive a short name and confirm with user
- Create worktree (e.g. `.codex/worktrees/<name>`)
- Inside worktree: `git checkout -b "<BRANCH_NAME>"`
- HARD GATE: never use `-B` (force overwrite). If the branch already exists, STOP and ask the user.

## Phase 1: Clarify only when wrong assumptions waste work
Default: state assumptions and proceed.

Ask only when:
- two plausible interpretations lead to materially different implementations
- a destructive or hard-to-reverse choice must be made
- the user's intent is genuinely ambiguous, not just underspecified
- a spec or requirement could be read in conflicting ways that affect correctness

Rules:
- ask at most 5 concise questions, batched in one message
- do not ask about naming, style, or minor scope unless it blocks implementation
- if a reasonable default path exists, state assumptions briefly and proceed

If -quick is set:
- prefer assumptions over questions
- still ask if the choice is destructive or truly ambiguous

## Phase 2: Plan (auto-select depth)

Assess task complexity and choose the cheapest acceptable path:

### solo (no subagents)
When: change is local, requirement is clear, existing pattern is obvious.

### explore (one explorer subagent)
When: similar implementations must be found, touched area is not fully obvious, validation paths need discovery.

Explorer returns only:
- relevant files/modules
- reusable patterns/helpers
- likely impact points
- validation commands/tests

### design (explorer + architect subagents)
When: task spans multiple modules/layers, naming/boundary/abstraction choices matter, multiple plausible patterns exist.

Architect returns only:
- recommended placement of logic
- naming / interface guidance
- abstraction level to prefer
- rejected alternatives in 1-3 bullets

### Plan output
Produce a concise plan with:
- Goal
- Approach
- Files/areas likely touched
- Validation steps
- Assumptions (if any)

## Phase 3: Implement

Before writing new code, read neighboring files in the same layer and match their conventions.

During implementation:
- reuse existing helpers/patterns when they already solve the problem
- if your change makes nearby code inconsistent and the fix is local/safe, fix it in the same change
- keep scope within the same module/layer; do not cascade refactors
- do not over-engineer: avoid speculative fallbacks, premature abstraction, and unnecessary indirection — pick the simplest approach that solves the actual problem

### Checkpoint
After implementation, before moving to validation:
- Run `git diff --stat` and confirm changes match the plan
- If the diff is unexpectedly large or touches unplanned files, STOP and ask the user

## Phase 4: Validate
Run relevant tests/validation if available.
Then re-read the plan and verify each goal is met.

If -quick is set:
- keep validation lightweight, but still run the most relevant available check

## Final output
Return:
1. chosen depth (solo/explore/design)
2. short plan
3. assumptions/questions asked
4. implementation summary
5. validation summary
