---
name: explore
description: |
  Explore a repository without implementing changes.
  Use this for investigation, impact analysis, pattern discovery, and review preparation.
  Stay read-only unless the user explicitly asks otherwise.
---

# explore

Do repository exploration only. No implementation.

## Args
- solo: single module / local exploration
- pair: cross-cutting / multi-module exploration

If args are omitted:
- default to solo for narrow questions
- default to pair for architecture / dependency / impact questions

## Input

Provide the question and any supporting material together when invoking the skill:

```
explore pair

## Question
<what you want to investigate>

## Reference (optional)
- Specs / docs: <links or summaries>
- Domain context: <business rules, constraints>
- Related tickets: <links or IDs>
```

Reference material helps narrow the search and avoid false leads. If omitted, exploration relies solely on repo signals.

## Goal
Answer questions like:
- where is this responsibility implemented?
- what files/modules are likely affected?
- what conventions does this area follow?
- what is the impact range of changing X?
- what context do I need before reviewing an ADR or PR?

## Mode selection

### solo
Use when:
- the question is local
- only one module/layer is likely involved

Always:
- read neighboring files to confirm patterns (not just infer)
- trace dependency chains to verify impact

Return:
- relevant files/modules
- nearest similar implementations
- likely impact points

### pair
Use when:
- multiple modules/layers may be involved
- the question is about boundaries, ownership, or architecture
- impact analysis matters more than local code reading

Execution:
- split the exploration by module or layer boundary
- use subagents to explore each area in parallel
- merge findings into a single report

Always:
- trace dependency chains across module boundaries
- report secondary impact points beyond the obvious
- catalog relevant patterns thoroughly

Guardrail: report up to 15 key modules/boundaries. If more exist, summarize the remainder and note the count.

Return:
- relevant files/modules
- existing patterns/helpers
- dependency / layer boundaries involved
- likely impact points
- open questions / unknowns

## Exploration rules
- stay read-only
- prefer concrete findings over broad summaries
- read neighboring files to confirm local conventions
- do not drift into implementation planning — report findings and recommended next steps, but never propose code changes
- for each finding, tag confidence:
  - **confirmed**: directly observed in code (cite file/line)
  - **likely**: inferred from patterns or naming, not directly verified
  - **uncertain**: plausible but unverified — flag for manual check

## Output format

Explain using logical names first (e.g. "the authentication module", "the order processing pipeline"), then attach physical paths as supporting detail. Do not lead with file paths.

Return:
1. TL;DR (2-3 lines — logical overview of what was found and the answer to the user's question)
2. Scope
3. Key findings (each tagged confirmed / likely / uncertain)
   - describe each finding in logical terms first, then cite physical files/lines as evidence
4. Architecture / module map (logical names → physical paths)
5. Patterns/helpers to reuse
6. Likely impact points
7. Open questions / uncertainties
8. Recommended next step
