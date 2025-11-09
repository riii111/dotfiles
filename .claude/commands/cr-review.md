---
argument-hint: [--type <type>] (default: uncommitted)
---

# CodeRabbit CLI Review

Run CodeRabbit CLI to review code changes with AI-powered feedback.

## Arguments

Parse the provided arguments `$ARGUMENTS` to extract the `--type` option:
- If `--type <value>` is provided, use that value
- Supported types: `uncommitted`, `committed`, `all`
- Default: `uncommitted` if no `--type` is specified

## Execution

Execute the CodeRabbit CLI command:
```bash
cr --prompt-only --type <TYPE>
```

Where `<TYPE>` is determined from the arguments as described above.

## Example Usage

- `/cr-review` - Reviews uncommitted changes (default)
- `/cr-review --type uncommitted` - Explicitly reviews uncommitted changes
- `/cr-review --type committed` - Reviews committed changes
- `/cr-review --type all` - Reviews all changes (committed + uncommitted)

## Notes

- The `--prompt-only` flag optimizes output for AI agents like Claude Code
- CodeRabbit CLI analyzes code using the same pattern recognition that powers PR reviews
- Results will include actionable feedback and suggestions for improvements
