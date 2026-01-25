---
name: promote
description: Promote frequent learnings to rules
---

Scan files in `~/.claude/cache/learnings/` and suggest promotion candidates to rules.

**Important**: Project-specific learnings (`project != general`) are NOT eligible. Only general knowledge can be promoted.

## Promotion Criteria

Must satisfy ALL of:

1. **Frequency**: frequency >= 3 (encountered 3+ times)
2. **Maturity**: first_seen is 14+ days ago (not a one-week fluke)
3. **Recency**: last_seen is within 90 days (still relevant)
4. **Generality**: `project: general` only
5. **Status**: `status: active` only
6. **Importance**: Ignoring it would lead to bugs, incidents, or inefficiency

## Promotion Destination

`~/.claude/rules/learnings/{name}.md`

**Create folder if it doesn't exist.**

## Conversion on Promotion

Convert learning (specific case) to rule (generalized guideline).

### Conversion Example

**Original learning**:

    # Ktor RLS Transaction Issue

    ## Problem
    RLS policy not working inside Ktor transaction

    ## Cause
    set_config() was executed outside transaction scope

    ## Solution
    Call set_config() immediately after transaction starts

**Promoted rule**:

    # PostgreSQL RLS with Ktor

    ## Rule
    When using transactions in Ktor, call `set_config()` for RLS
    at the beginning of the transaction block.

    ## Reason
    If `set_config()`'s 3rd argument is `true` (transaction-local),
    executing it outside a transaction will not apply RLS.

    ## Correct Pattern
    ```kotlin
    transaction {
        exec("SELECT set_config('app.current_user_id', ?, true)", listOf(userId))
        // RLS is active for subsequent queries
    }
    ```

    ## Wrong Pattern
    ```kotlin
    exec("SELECT set_config('app.current_user_id', ?, true)", listOf(userId))
    transaction {
        // RLS not applied!
    }
    ```

## Execution Steps

1. Scan all files in `~/.claude/cache/learnings/`
2. List files meeting promotion criteria
3. Present proposed rule for each candidate
4. After user confirmation:
   a. Create in `~/.claude/rules/learnings/`
   b. Delete the original learning file

## Output Format

### Promotion Candidates

| File | freq | first_seen | last_seen | Reason |
|------|------|------------|-----------|--------|
| xxx.md | 3 | 2024-12-01 | 2025-01-20 | [reason] |

### Skipped

| File | Skip Reason |
|------|-------------|
| yyy.md | Frequency too low (2) |
| zzz.md | Too recent (first_seen < 14 days) |
| aaa.md | Stale (last_seen > 90 days) |
| bbb.md | Project-specific |
| ccc.md | Archived |
