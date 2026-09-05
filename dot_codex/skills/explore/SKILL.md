---
name: explore
description: Explore a repository without implementing changes. Use for repository investigation, impact analysis, and pattern discovery.
---

# Explore

Answer the user's repository question with evidence while keeping the working tree unchanged.

## Investigation

- Read the applicable `AGENTS.md` and repository guidance.
- Search for the named behavior, symbols, and related concepts. Inspect neighboring code before treating a local pattern as a convention.
- Trace callers, data flow, dependencies, and configuration far enough to distinguish direct effects from secondary effects.
- Compare with the nearest relevant implementations when the question concerns conventions or reuse.
- Stop when the evidence answers the question. Do not expand the task into an exhaustive repository inventory.

Remain read-only. Do not edit files, create commits, change branches, or mutate external state as part of this workflow.

## Subagents

- When delegation helps, use `gpt-5.6-luna` with `xhigh` reasoning by default. Give each Luna agent a narrow, independently verifiable, non-overlapping responsibility such as one module, dependency edge, or hypothesis; using several focused agents is acceptable.
- Use `gpt-5.6-sol` or a more capable model sparingly, when a broader cross-cutting question benefits from one agent holding more context and synthesizing it coherently. Its responsibility may be correspondingly broader.
- Before launching a Sol-or-higher subagent, state the model and why the broader or harder assignment justifies it. This is a visibility requirement, not an approval gate.
- Synthesize results and resolve gaps between subagent scopes in the parent task.

## Reporting

Lead with the answer, then cite the smallest useful set of files and lines. Use logical component names before paths. Separate direct observations from inference, state material uncertainty, and mention unresolved gaps only when they affect the answer. Recommend a next step only when it follows from the findings.
