---
description: Comprehensive PR review for code quality, tests, and error handling
argument-hint: "[ASPECTS=all] [parallel]"
---

# Comprehensive PR Review

Run a comprehensive pull request review focusing on multiple aspects of code quality.

**Review Aspects (optional):** $ARGUMENTS

## Review Workflow

### 1. Determine Review Scope

- Check git status to identify changed files: `git diff --name-only`
- Check if PR already exists: `gh pr view` (if applicable)
- Parse arguments to see if user requested specific review aspects
- Default: Run all applicable reviews

### 2. Available Review Aspects

- **comments** - Analyze code comment accuracy and maintainability
- **tests** - Review test coverage quality and completeness
- **errors** - Check error handling for silent failures
- **types** - Analyze type design and invariants (if new types added)
- **code** - General code review for project guidelines
- **simplify** - Simplify code for clarity and maintainability
- **all** - Run all applicable reviews (default)

### 3. Identify Changed Files

Run these commands to understand the scope:
```bash
git diff --name-only
git diff --stat
```

### 4. Execute Reviews Based on Aspects

#### Architecture Review (always applicable)

- Verify that changes respect the project's architectural boundaries in the touched area (layering, module boundaries, dependency direction)
- If a "pure" layer is directly doing I/O or data access, always report and propose extracting to the appropriate data-access layer

#### Issue Alignment Review (required if issue/spec docs are provided)

- Verify the implementation approach aligns with the issue/spec proposals
- If not aligned, call out the reason and risk

#### Code Review (always applicable)

Review code against project guidelines with high precision:

- **Project Guidelines Compliance**: Check AGENTS.md or equivalent for import patterns, framework conventions, language-specific style, function declarations, error handling, logging, testing practices
- **Bug Detection**: Logic errors, null/undefined handling, race conditions, memory leaks, security vulnerabilities, performance problems
- **Code Quality**: Code duplication, missing critical error handling, accessibility problems, inadequate test coverage

Rate each issue from 0-100 (only report issues with confidence ≥ 80):
- 91-100: Critical bug or explicit guideline violation
- 76-90: Important issue requiring attention
- 51-75: Valid but low-impact issue

#### Test Analysis (if test files changed)

> **Note: Do not run tests. Test execution is handled by CI. Review test code quality only.**

Focus on behavioral coverage rather than line coverage:

- Untested error handling paths
- Missing edge case coverage
- Uncovered critical business logic branches
- Missing negative test cases
- Tests coupled to implementation instead of behavior

Rate criticality 1-10:
- 9-10: Critical functionality (data loss, security, system failures)
- 7-8: Important business logic (user-facing errors)
- 5-6: Edge cases (minor issues)
- 3-4: Nice-to-have coverage

#### Error Handling Analysis (if error handling changed)

Hunt for silent failures:

- Empty catch blocks (absolutely forbidden)
- Catch blocks that only log and continue
- Returning null/undefined/default values on error without logging
- Optional chaining that silently skips failing operations
- Fallback chains without explanation
- Retry logic without user notification

For each issue, identify:
- Severity: CRITICAL (silent failure), HIGH (poor error message), MEDIUM (missing context)
- Hidden errors that could be caught
- User impact
- Specific fix recommendation

#### Comment Analysis (if comments/docs added)

Verify comment accuracy:

- Cross-reference claims against actual code
- Check function signatures match documented parameters
- Verify described behavior aligns with code logic
- Identify comment rot and outdated references
- Flag comments that merely restate obvious code

#### Type Design Analysis (if types added/modified)

Evaluate type design quality:

- Encapsulation (1-10): Are internals properly hidden?
- Invariant Expression (1-10): Are constraints clear from the type?
- Invariant Usefulness (1-10): Do invariants prevent real bugs?
- Invariant Enforcement (1-10): Are invariants checked at construction?

#### Code Simplification (after passing review)

Simplify for clarity and maintainability:

- Reduce unnecessary complexity and nesting
- Eliminate redundant code
- Improve naming
- Avoid nested ternary operators
- Preserve all functionality

### 5. Aggregate Results

Structure findings as:

```markdown
# PR Review Summary

## Critical Issues (X found)
- [aspect]: Issue description [file:line]

## Important Issues (X found)
- [aspect]: Issue description [file:line]

## Suggestions (X found)
- [aspect]: Suggestion [file:line]

## Strengths
- What's well-done in this PR

## Recommended Actions
1. Fix critical issues first
2. Address important issues
3. Consider suggestions
4. Re-run review after fixes
```

## Usage Examples

**Full review (default):**
```
/pr-review
```

**Specific aspects:**
```
/pr-review ASPECTS=tests,errors
/pr-review ASPECTS=comments
/pr-review ASPECTS=simplify
```

## Tips

- **Run early**: Before creating PR, not after
- **Focus on changes**: Analyze git diff by default
- **Address critical first**: Fix high-priority issues before lower priority
- **Re-run after fixes**: Verify issues are resolved
- **Use specific reviews**: Target specific aspects when you know the concern
