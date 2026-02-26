---
description: PR Review - structured feedback for pull requests, applicable to any language or stack
argument-hint: [additional instructions / language-specific guidelines]
disable-model-invocation: true
---

# PR Review

Review a PR with structured feedback, applicable to any language or stack.

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

### Code Quality & Best Practices
- Error handling: appropriate use of language-specific patterns (exceptions, Result types, etc.)
- Readability: clear naming, consistent formatting, appropriate abstraction level
- DRY principle: no unnecessary duplication
- SOLID principles where applicable
- Language idioms: follows conventions of the language/framework in use

### Performance
- Unnecessary computations or memory allocations
- Efficient data structures and algorithms
- Appropriate caching or memoization where beneficial
- N+1 queries or similar anti-patterns in data access

### Testing
- Adequate coverage for new/modified logic
- Edge cases and error paths covered
- Tests are deterministic and environment-independent

### Maintainability
- Naming is clear and follows project conventions
- Abstraction level is appropriate (neither over/under-engineered)
- Public APIs are documented

### Security & Stability
- Input validation and sanitization
- No hardcoded secrets or credentials
- Breaking changes (if any) are documented and justified
- Dependencies: versions are reasonable, no known vulnerabilities

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
