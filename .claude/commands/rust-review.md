---
argument-hint: [additional instructions]
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

## Additional Instructions

$ARGUMENTS
