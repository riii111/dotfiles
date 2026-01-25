---
name: learn
description: Extract learnings from session and save to ~/.claude/cache/learnings/
---

Review this session and extract learnings.

**Important: All file content (YAML/Markdown) must be written in English** for token efficiency.

## Extraction Criteria

### Extract
- Non-obvious discoveries from error resolution
- User corrections or feedback
- Workarounds and alternative solutions
- Effective debugging techniques
- Project-specific patterns
- Anything that passes: "Would this help if I encounter the same problem in 6 months?"

### Do NOT Extract
- Simple typo fixes
- One-time fixes (not reproducible)
- Temporary external API issues
- Things easily found in documentation
- Plain implementation work (no learning)

## Save Location

- General: `~/.claude/cache/learnings/general/`
- Project-specific: `~/.claude/cache/learnings/{project-name}/`

**Create folder if it doesn't exist.**

## File Format

Filename: `{kebab-case-name}.md`

```yaml
---
name: {kebab-case-name}
description: |
  {Specific trigger conditions. Include error messages, symptoms, keywords.
  Write to match easily during /recall search.}
first_seen: {YYYY-MM-DD}
last_seen: {YYYY-MM-DD}
frequency: 1
tags: [{kotlin, postgresql, gcp, terraform, etc.}]
project: {general | project-name}
status: active
---

# {Title}

## Problem
{What happened. Include specific error messages if available.}

## Cause
{Why it happened. Root cause explanation.}

## Solution
{How it was resolved. Include code examples if applicable.}

## Verification
{How to confirm the fix worked.}
```

### Field Descriptions

| Field | Description |
|-------|-------------|
| `first_seen` | Date when first encountered |
| `last_seen` | Date when last encountered (update on frequency++) |
| `frequency` | Number of times encountered |
| `status` | `active` / `archived` |

## Frequency Update Rules

**Always check for existing files before creating new ones.**

1. Glob search under `~/.claude/cache/learnings/`
2. If a file on the same topic exists (see criteria below):
   - Increment `frequency` by 1
   - Update `last_seen` to today
   - Update/supplement content as needed
   - **Do NOT create a new file**
3. Create new file only if no match found

### Same Topic Criteria

Files are considered "same topic" if ANY of:
- Same error message or error code
- Same library/tool + same problem category
- Same root cause (even if symptoms differ)

## Execution Steps

1. Review the session conversation
2. Determine if there are learnings matching extraction criteria
3. If learnings exist:
   a. Determine save location (general or project-specific)
   b. Create folder if it doesn't exist
   c. Check for existing files on the same topic
   d. Create or update file
4. If no learnings: report "No learnings to extract from this session"

**Note**: Don't force extraction if there's nothing to learn. Quality > Quantity.
