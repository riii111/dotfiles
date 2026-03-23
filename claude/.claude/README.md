# Claude Code Configuration

Settings are split into two files:
- **settings.base.json** - Shared config (symlinked from dotfiles)
- **settings.local.json** - Machine-specific paths (created per machine)

The `claude` wrapper in `.zshrc` auto-merges them into `settings.json` on launch.

## Setup

1. Symlink to `~/.claude/`:
   ```bash
   ln -s /path/to/dotfiles/.claude/commands ~/.claude/commands
   ln -s /path/to/dotfiles/.claude/agents ~/.claude/agents
   ln -s /path/to/dotfiles/.claude/hooks ~/.claude/hooks
   ln -s /path/to/dotfiles/.claude/settings.base.json ~/.claude/settings.base.json
   ```
2. Create `~/.claude/settings.local.json`:
   ```bash
   cp /path/to/dotfiles/.claude/settings.local.json.example ~/.claude/settings.local.json
   # Edit: replace YOUR_USER_NAME with actual username
   ```
3. Open a new shell (or run `exec zsh`) to load the `claude` wrapper
4. Setup periodic promotion (optional, see below)

## Key Features

### Second Opinion

Get independent perspectives from other LLMs.

- `/codex-2nd` - Get Codex's repo-aware opinion on current discussion
- `/ask` - Feasibility check with structured questions before implementation

### Review & Risk Analysis

- `/cr` - CodeRabbit CLI review for quick diff analysis
- `/premortem` - Assume failure happened, find causes and mitigations

### Plan-CoVe

Structured implementation with checkpoints: branch → plan → Codex review → implement per phase.

- `/plan-cove` - CoVe loop with mandatory review gates and per-phase commits

### Continuous Learning

```
/learn   → Save to cache/learnings/
/recall  → Search past learnings (use when facing similar errors or problems)
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
