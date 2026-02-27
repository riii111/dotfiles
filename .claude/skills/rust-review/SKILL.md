---
description: Rust PR Review - structured Rust-specific feedback for pull requests
argument-hint: [additional instructions]
disable-model-invocation: true
---

# Rust PR Review

Review a Rust PR with structured feedback.

## Context Gathering

1. Fetch PR metadata (title, body, base branch):
   ```bash
   gh pr view --json title,body,baseRefName
   ```

2. Generate full diff against base branch:
   ```bash
   git diff $(gh pr view --json baseRefName -q .baseRefName)..HEAD
   ```

3. Read modified files directly for detailed context

## Review Criteria

Evaluate all applicable aspects below.

### Correctness
- Does the code fulfill the PR's stated purpose?
- Any logic errors, edge cases, or unhandled conditions?

### Rust Idioms & Best Practices
- Error handling: use Result/Option; avoid unwrap/expect in library code
- Ownership: unnecessary clones, missing borrows, ownership transfer semantics
- Lifetimes: explicit only when necessary, no premature 'static bounds
- Pattern matching: exhaustive and idiomatic (if-let, while-let, matches!)
- Unsafe blocks: justified and minimal, with documented invariants

### Performance
- Unnecessary allocations (String vs &str, Vec vs slice)
- Iterator chains vs manual loops
- Appropriate use of Cow, Arc, Rc for shared/cheap-cloneable types

### Testing
- Adequate coverage for new/modified logic
- Edge cases and error paths covered
- Tests are deterministic and environment-independent

### Maintainability
- Naming is clear and follows Rust conventions
- Abstraction level is appropriate (neither over/under-engineered)
- Public APIs are documented

### Security & Stability
- Input validation and sanitization
- No hardcoded secrets or credentials
- Breaking changes (if any) are documented and justified
- Dependency versions: constraints are reasonable, no yanked crates

## Output Format

Structure your review as follows:

### Summary
(1-2 sentences: what this PR accomplishes)

### Findings
List issues by severity (omit empty categories):

- **Critical**: Must address before merge
- **Warning**: Should address, non-blocking
- **Suggestion**: Nice-to-have improvements

### Verdict
**APPROVE** | **REQUEST_CHANGES** | **COMMENT**

---

## Output Destination

**IMPORTANT**: Write review results to a file, not just stdout.

### File Path

```
reviews/{branch}/cc-rev.md
```

Where `{branch}` is the current git branch name (from `git branch --show-current`).

Create the directory if it does not exist: `mkdir -p reviews/$(git branch --show-current)`

### File Format

Follow the format defined in `.claude/reviews/TEMPLATE.md`:

- Header: `# Review: {branch}` with `<!-- reviewer: cc-rev -->`
- Each finding: `## [C1] file:line` (sequential IDs)
- Wrap each thread body in `~~~` fences
- Use `### cc-rev` before your comment (the `impl` section will be filled by the implementation AI)
- Code snippets use ` ``` ` inside the `~~~` fences

### Post-Review Notification

Notification to the implementation AI is handled automatically by a PostToolUse hook.
No manual `tmux send-keys` command is needed from this reviewer.

---

## Additional Instructions

$ARGUMENTS
