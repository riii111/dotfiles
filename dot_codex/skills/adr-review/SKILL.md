---
name: adr-review
description: |
  Review an ADR with parallel perspectives when helpful.
  Optimize for fast context building, pragmatic critique, and clear review output.
---

# adr-review

Review an ADR pragmatically.

## Args
- solo: single-agent review
- pair: context-reader + architect-reviewer
- team: context-reader + architect-reviewer + pragmatic-reviewer

If args are omitted, Triage determines the tier and modifiers automatically.

## Input

Provide the ADR and any supporting context together when invoking the skill:

```
adr-review

## ADR
<ADR link or body>

## Context (optional)
- Epic / user story: <summary or link>
- Domain info: <relevant business rules, constraints>
- Prior decisions: <related ADRs, Slack threads, etc.>
```

Context helps reviewers distinguish "intentional decision" from "oversight". If omitted, reviewers will note gaps as **unverified**.

## Triage (run first)

Before assembling the team:

1. If the user specified a tier and modifiers explicitly, use them as-is.
2. Otherwise, infer from the ADR content, provided context, and repo:
   - Does the ADR reference an Epic, user story, or acceptance criteria? → requirement-driven
   - Is the ADR about refactoring, performance, or tech debt? → technical improvement
   - Does the ADR touch auth/authz, data exposure, tenancy, secrets, or trust boundaries? → add security-reviewer
   - If genuinely ambiguous after reading the ADR, ask the user.
3. Select tier and modifiers based on inference:

| ADR type | Scope | Tier | req | sec |
|---|---|---|---|---|
| requirement-driven | single module | solo | on | auto |
| requirement-driven | cross-cutting+ | pair–team | on | auto |
| technical improvement | single module | solo | off | auto |
| technical improvement | cross-cutting+ | pair | off | auto |

`auto` = include security-reviewer if the ADR touches auth/authz/data/secrets/trust boundaries.

## Reviewer roles

### context-reader
**Runs first.** Output is passed to all subsequent reviewers as shared context.

Gather:
- current architecture relevant to the ADR
- existing patterns / helpers / prior art
- affected modules / layers / boundaries

For each assumption in the ADR, classify as:
- **verified**: confirmed by repo evidence (cite file/line)
- **unverified**: references external specs, other teams' APIs, SLAs, or information not in the repo
- **contradicted**: conflicts with current repo state

### architect-reviewer
Review:
- responsibility boundaries and placement of logic
- abstraction level
- alternatives considered / missing
- long-term consistency with the codebase
- whether the ADR actually solves the problem it states

### requirements-reviewer
Auto-assigned by triage when the ADR is requirement-driven. Skipped for purely technical ADRs.

Review:
- does the proposal satisfy the stated requirements / acceptance criteria?
- are requirements missing, ambiguous, or silently narrowed?
- are there requirements that the proposal over-solves or gold-plates?

### pragmatic-reviewer
Review:
- implementation realism
- migration / rollout difficulty
- operational burden
- whether the proposal is too idealized for the actual need
- whether a smaller step would get most of the value now

### security-reviewer
Auto-assigned by triage when relevant. No user action needed.

Review:
- auth/authz boundaries
- data exposure / tenancy / secrets / config
- unsafe assumptions around trust boundaries

## Review rules
- do not ask for perfect architecture
- distinguish "incorrect or risky now" from "could be improved later"
- prefer concrete critique tied to current repo context
- when context is missing, report it as **unverified** — never fill gaps with plausible-sounding guesses
- suggest the smallest viable correction when possible

## Output format

Each review item uses a severity prefix:

| Prefix | Meaning |
|---|---|
| **MUST** | Blocking — must be resolved before approval |
| **SHOULD** | Strong recommendation — risky to ignore |
| **IMO** | Reviewer's opinion — take or leave |
| **NITS** | Minor style / naming / wording |
| **Q** | Question — needs clarification from the author |

Return:
- Summary judgment
- Review items (each prefixed with severity)
- Unverified assumptions
- Alternatives or narrower options

### Example

```
## Summary
The proposal is sound for the stated scope but relies on two unverified assumptions about the billing API contract.

## Review items
- **MUST**: ADR assumes idempotent PUT on /billing/plans, but no contract or test confirms this. If not idempotent, the retry logic in §3 will cause duplicate charges.
- **SHOULD**: Migration script lacks a rollback step — add one before merging.
- **IMO**: Consider feature-flagging the new path to allow gradual rollout.
- **NITS**: §2 "the service" is ambiguous — specify which service.
- **Q**: §4 claims "performance is acceptable" — what benchmark target is this measured against?

## Unverified assumptions
- Billing API idempotency (no contract found in repo)
- Upstream rate limits (referenced but not documented)

## Alternatives
- Narrower option: implement only the read path first, defer write path to next iteration.
```
