---
argument-hint: [c=committed|a=all] [base-branch] (default: uncommitted)
---

# CodeRabbit CLI Review (Short Command)

Run CodeRabbit CLI to review code changes with AI-powered feedback.

## Arguments

Parse the provided arguments `$ARGUMENTS`:

### Type (optional, first positional argument if single char)
- `u` → `uncommitted` (default if omitted)
- `c` → `committed`
- `a` → `all`

### Base Branch (optional)
- Any argument that is NOT `u`, `c`, or `a` is treated as base branch
- Passed to `--base <branch>`

### Examples of argument parsing
- (empty) → type=uncommitted, base=none
- `c` → type=committed, base=none
- `main` → type=uncommitted, base=main
- `c main` → type=committed, base=main
- `a develop` → type=all, base=develop

## Execution

Execute the CodeRabbit CLI command with a longer timeout (3 minutes):
```bash
cr --prompt-only [-t <TYPE>] [--base <BRANCH>]
```

Use `timeout: 180000` as CodeRabbit may take 1-2 minutes to complete.

## Output Interpretation

- If the output shows `Review completed ✔` with no other feedback, it means **no issues were found**. This is a successful review with zero suggestions.

## Usage Examples

- `/cr` - Reviews uncommitted changes (default)
- `/cr c` - Reviews committed changes
- `/cr a` - Reviews all changes
- `/cr main` - Reviews uncommitted changes compared to main branch
- `/cr c main` - Reviews committed changes compared to main branch
