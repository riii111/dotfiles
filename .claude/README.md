# Claude Code Configuration

## Setup

1. Symlink directories to `~/.claude/`
2. Add Stop hook to `~/.claude/settings.json` (see `settings.json` for reference)
3. Setup periodic promotion (optional, see below)

## Continuous Learning

```
/learn   → Save to cache/learnings/
/recall  → Search past learnings
/promote → Promote to rules/learnings/ (auto-loaded)
```

## Periodic Promotion

Weekly batch to check promotion candidates.

**Note:** `-p` mode doesn't support slash commands. Use descriptive prompts instead.

```bash
mkdir -p ~/.claude/logs

# Add to crontab (crontab -e)
0 9 * * 1  claude -p "Scan ~/.claude/cache/learnings/ for promotion candidates. Criteria: frequency >= 3, first_seen 14+ days ago, last_seen within 90 days, project=general, status=active. List candidates in a table." --allowedTools "Read,Glob,Grep" >> ~/.claude/logs/promote.log 2>&1
```
