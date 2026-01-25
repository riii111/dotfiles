---
name: recall
description: Search and reference past learnings
---

Search files in `~/.claude/cache/learnings/` and display relevant learnings.

## Usage

```
/recall {search keywords}
/recall "PrismaClientKnownRequestError"
/recall kotlin transaction
```

## Search Targets

1. **description** keywords
2. **tags**
3. **filename**
4. **content** (Problem, Cause, Solution)

## Search Steps

1. Scan all `.md` files under `~/.claude/cache/learnings/`
2. Filter: `status: active` only (skip `archived`)
3. Extract files matching keywords
4. Sort by relevance (description > tags > content)

## Output Format

### Search Results: "{keyword}"

**Found: {N} learnings**

#### 1. {Title}
- **File**: `{path}`
- **Project**: {general | project-name}
- **First seen**: {YYYY-MM-DD}
- **Last seen**: {YYYY-MM-DD}
- **Frequency**: {N}
- **Summary**: {One-line summary of problem and solution}

---

Specify a file if you want to see details.

## When No Match

"No relevant learnings found. Use /learn to record new discoveries."

## Archiving Stale Learnings

If a learning hasn't been encountered for 180+ days (`last_seen` is old), suggest archiving:

"This learning hasn't been encountered since {date}. Archive it? (set status: archived)"
