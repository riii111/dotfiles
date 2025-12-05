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

**IMPORTANT: You MUST run this command as a background task using `run_in_background: true`**

Execute the CodeRabbit CLI command:
```bash
cr --prompt-only [-t <TYPE>] [--base <BRANCH>]
```

After starting the background task, monitor it with `BashOutput` and report the results when complete.

## Usage Examples

- `/cr` - Reviews uncommitted changes (default)
- `/cr c` - Reviews committed changes
- `/cr a` - Reviews all changes
- `/cr main` - Reviews uncommitted changes compared to main branch
- `/cr c main` - Reviews committed changes compared to main branch
