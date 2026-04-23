---
name: adr-review
description: |
  Review an ADR with claim-first evidence gathering and pragmatic critique.
  Optimize for repeatable investigation, calibrated severity, and postable comments.
---

# adr-review

Review an ADR pragmatically.

Use a fixed pipeline:
1. Triage the ADR and decide how deep the investigation should go.
2. Build a claim table from the ADR before judging it.
3. Gather evidence only for the claims that matter.
4. Convert concerns into calibrated review items.
5. Return postable comment drafts, not just raw concerns.

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
   - If the investigation scope is genuinely ambiguous after reading the ADR, ask the user whether to inspect infra, live signals, or split work with subagents.
3. Select tier and modifiers based on inference:

| ADR type | Scope | Tier | req | sec |
|---|---|---|---|---|
| requirement-driven | single module | solo | on | auto |
| requirement-driven | cross-cutting+ | pair–team | on | auto |
| technical improvement | single module | solo | off | auto |
| technical improvement | cross-cutting+ | pair | off | auto |

`auto` = include security-reviewer if the ADR touches auth/authz/data/secrets/trust boundaries.

### Heavy vs light review

Use a light flow when the ADR is narrow and mostly repo-local:
- require `claim table`
- confirm against `repo`
- skip the full evidence matrix unless a claim stays ambiguous or high impact

Use a heavy flow when the ADR is cross-cutting or makes operational claims:
- expand to a full evidence matrix
- track dropped / weakened items
- draft postable comments explicitly

Treat these as signals for a heavy flow:
- performance, cost, migration, monitoring, rollback, or availability claims
- claims about current pain such as "frequent", "high load", "alert-heavy", "costly", "slow", or "many incidents"
- cross-repo dependencies or trust-boundary changes

## Claim table (required)

Do this before gathering evidence or drafting review items.

Break the ADR into **decision-relevant claims**, not sentences.
- Split one sentence into multiple claims when it makes multiple assertions.
- Merge multiple sentences when they support one decision claim.

Use fixed tags first, then add others only if needed.
- default tags: `performance`, `cost`, `migration`, `permission`, `monitoring`, `rollback`, `scope`, `integration`
- optional tags: `operations`, `availability`, `security`, `data-integrity`, `other`

Each claim should capture:
- claim id
- claim text
- tag
- why it matters to the decision

Example:
- `C1`: "AlloyDB will materially reduce current alert noise" (`monitoring`)
- `C2`: "Most daytime issues are CPU or memory driven, not replica lag" (`performance`)

## Evidence collection

For each claim, decide which evidence sources are needed before reviewing it.

### Source selection rules

- `repo`: almost always required
- `infra`: required when the ADR touches operations, monitoring, permissions, rollout, external integrations, or environment shape
- `docs`: required when the ADR relies on vendor behavior, product limits, or external contracts
- `live`: required only when the ADR makes claims about current reality using words like "frequent", "high", "many", "expensive", or "degraded"

If the right source is still unclear after reading the ADR, ask the user a narrow question instead of guessing.

### Evidence matrix

Use a matrix when the ADR is heavy or cross-cutting. For each claim, record:
- source checked: `repo / infra / docs / live`
- result: `supported / contradicted / unverified`
- short evidence note

Prefer the smallest sufficient investigation. Do not inspect `infra`, `docs`, or `live` just because they exist.

## Reviewer roles

### context-reader
**Runs first.** Output is passed to all subsequent reviewers as shared context.

Gather:
- current architecture relevant to the ADR
- existing patterns / helpers / prior art
- affected modules / layers / boundaries

Start from the claim table, then gather evidence.

For each claim, classify the current support level as:
- **supported**: evidence backs the claim
- **contradicted**: evidence conflicts with the claim
- **unverified**: needed evidence is missing or outside the available context

Then summarize the repo-relevant architecture and assumptions that later reviewers should inherit.

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

## Comment distillation (required)

Do not turn a vague concern directly into a review comment.

For each concern, walk this sequence:
1. Identify the claim it targets.
2. Classify the concern type:
   - `factual-error`
   - `insufficient-evidence`
   - `scope-gap`
   - `overstatement`
   - `missing-precondition`
3. Reduce it to the smallest proposition that the evidence actually supports.
4. Decide whether to keep it, weaken it, or drop it.
5. Only then assign severity and draft the comment.

Typical pruning rules:
- abstract alarm with no concrete failure mode -> split or drop
- stronger-than-evidence assertion -> weaken
- high-impact but weakly supported concern -> move to **unverified assumptions** instead of escalating

Track dropped or weakened items for heavy ADRs so the user can see what was intentionally not posted.

## Severity calibration

Calibrate severity using **impact x evidence strength**.

| Impact x evidence | Severity |
|---|---|
| high impact + strong evidence | **MUST** |
| medium impact + strong evidence | **SHOULD** |
| high impact + medium evidence | **SHOULD** |
| low impact + strong evidence | **NITS** |
| medium impact + weak evidence | **NITS** or **Q** |
| high impact + weak evidence | move to **unverified assumptions** |

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
- Claim table
- Evidence matrix when the ADR is heavy
- Review item candidates
- Review items (each prefixed with severity)
- Comment drafts that are ready to post
- Unverified assumptions
- Alternatives or narrower options
- Dropped / weakened items when useful

### Example

```
## Summary
The proposal is sound for the stated scope but relies on two unverified assumptions about the billing API contract.

## Claim table
- C1: Billing API supports idempotent PUT for plan updates. (`integration`)
- C2: The migration can be rolled out safely without a feature flag. (`migration`)

## Evidence matrix
- C1 / repo: unverified — no contract test or client guarantee found.
- C2 / repo: contradicted — current retry path assumes retries may re-enter write logic.

## Review item candidates
- C1: insufficient-evidence -> likely SHOULD
- C2: missing-precondition -> MUST

## Review items
- **MUST**: ADR assumes idempotent PUT on /billing/plans, but no contract or test confirms this. If not idempotent, the retry logic in §3 will cause duplicate charges.
- **SHOULD**: Migration script lacks a rollback step — add one before merging.
- **IMO**: Consider feature-flagging the new path to allow gradual rollout.
- **NITS**: §2 "the service" is ambiguous — specify which service.
- **Q**: §4 claims "performance is acceptable" — what benchmark target is this measured against?

## Comment drafts
- Global comment: "The proposal direction looks reasonable, but two decision-critical assumptions remain unverified: billing API idempotency and rollback safety. Please either add evidence or narrow the claim."

## Unverified assumptions
- Billing API idempotency (no contract found in repo)
- Upstream rate limits (referenced but not documented)

## Alternatives
- Narrower option: implement only the read path first, defer write path to next iteration.

## Dropped / weakened items
- Dropped: "billing service design feels risky" — too abstract without a concrete failure mode.
- Weakened: "retry path is broken" -> "retry safety is unverified until idempotency is confirmed".
```
