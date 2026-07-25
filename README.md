# dotfiles

Dev environment for macOS, managed by chezmoi.

![nvim](https://github.com/user-attachments/assets/0511c1be-2d3a-4b09-a14a-10a1e5f715ad)


## Setup

```bash
brew install chezmoi
chezmoi init --source ~/ghq/github.com/riii111/dotfiles
chezmoi apply
# Install Nix first: https://nixos.org/download/
~/bin/dotctl sync-nix-profile
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/ghq/github.com/riii111/dotfiles#personal
exec zsh
```

### Work tools (optional)

Private work tool layers are managed separately.

```bash
~/bin/dotctl work-tools install
~/bin/dotctl work-tools update
```

### Herdr WezTerm status (optional)

Install the release binary at `~/.local/bin/wezterm-git-status-bridge`, then run its `setup --herdr` command. The generated configuration and shell hook use this path; replace the binary in place when updating it.

Herdr needs a one-time plugin link per machine to fire the events that feed the WezTerm right-status git info inside herdr panes.

```bash
herdr plugin link ~/ghq/github.com/riii111/wezterm-git-status-bridge/contrib/herdr-plugin
```

### Finder integration (optional)

Route Finder double-clicks to WezTerm + Neovim / VisiData.

```bash
bash ~/ghq/github.com/riii111/dotfiles/scripts/build-open-apps.sh
bash ~/ghq/github.com/riii111/dotfiles/scripts/setup-default-apps.sh
```

Routing: text / code → Neovim, csv / tsv → csvlens, parquet / sqlite / jsonl → VisiData, images / pdf → Preview (untouched). Re-run both scripts after a macOS update if associations break.

Markdown clipboard-to-image paste: `<C-v>` in normal mode (uses `pngpaste`, managed by the Nix CLI profile).

## Nix

Daily CLI tools are managed by the default user Nix profile.

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Homebrew stays for GUI / cask packages and is managed by nix-darwin.

### Codex task orchestration

Register the parent session and install the task tools:

```bash
ghq get https://github.com/riii111/codex-task-orchestrator
chezmoi apply
~/bin/dotctl sync-nix-profile
codex-task-orchestrator init
```

`init` asks for the parent session, orchestration ID, task source, allowed pull-request
repositories, and allowed agent tools. Add `cursor-cli` when Cursor is permitted for the
selected repositories; it is not selected automatically. The six task-orchestration skills in
`~/.codex/skills` are symlinked from the local `codex-task-orchestrator` checkout. Pull that
repository to update the suite, then run `chezmoi apply` to install or repair the links.

Cursor CLI's `agent` executable is installed and authenticated separately from this Nix profile.
When `cursor-cli` is allowed, install it through Cursor's supported installer and verify the
executable used by Herdr:

```bash
command -v agent
agent --version
```

Choose the worker in each JSON task specification:

```text
Codex:  agent_tool = codex,      runner = codex-app
Cursor: agent_tool = cursor-cli, runner = herdr
```

Start and inspect a worker with the shared CLI:

```bash
codex-task-orchestrator worker start <orchestration-id> task.json
codex-task-orchestrator worker status <orchestration-id> <task-id> --json
codex-task-orchestrator worker send <orchestration-id> <task-id> \
  --message 'Prioritize API compatibility'
codex-task-orchestrator worker stop <orchestration-id> <task-id>
codex-task-orchestrator worker resume <orchestration-id> <task-id>
```

For a Cursor worker, `herdr` owns the workspace and pane while Cursor CLI's `agent` owns the
conversation. Attach to Herdr with `herdr`, open the worker pane, and send direct instructions
there when needed. The parent `worker send` command reaches the same Cursor session. `stop` and
`resume` affect only that worker; `stop` is supported for Herdr workers.

Record the worker's events and recover delivery explicitly:

```bash
codex-task-orchestrator worker escalate <orchestration-id> <task-id> --message '<reason>'
codex-task-orchestrator worker record-pr <orchestration-id> <task-id> \
  --repository owner/repository --number <number> --url <url> \
  --verification '<checks>'
codex-task-orchestrator worker record-completion-note <orchestration-id> <task-id>
codex-task-orchestrator worker retry-operation <orchestration-id> <task-id>
codex-task-orchestrator worker retry-parent-delivery <orchestration-id> <task-id>
```

If startup or delivery is uncertain, inspect `worker status --json` and do not start a second
worker or switch automatically to Codex. A pending provider operation is retried with
`retry-operation`; a pending parent event is retried with `retry-parent-delivery`, not by polling.
After a merged pull request, the saved Completion Note and parent event drive the next task.
`manual` keeps the pull request in Draft; `auto` proceeds only after the current checks and
conflict state pass.

This setup has no periodic merge poller, merge scanner, or task LaunchAgent.

Reset one orchestration when its tracked state should be discarded:

```bash
codex-task-orchestrator reset codex-task-orchestration
```

`reset` destructively discards that orchestration's tracked sessions and Completion Notes; Completion Notes for other orchestrations remain.

### Store maintenance

nix-darwin runs weekly store maintenance for every host: GC deletes profile generations older than 30 days at 03:15 on Sunday, and store optimisation hard-links duplicate files at 04:15 on Sunday.

```bash
nix-collect-garbage --delete-older-than 30d --dry-run
# After darwin-rebuild switch:
sudo launchctl print system/org.nixos.nix-gc
sudo launchctl print system/org.nixos.nix-optimise
```

### Dev shell

Use the repo shell when you want the flake-pinned toolchain explicitly.

```bash
nix develop
nix develop -c ./bin/executable_dotctl test
```

## Features

### zsh

- Deferred `compinit` after prompt display
- Cache regeneration only on config change
- Modern CLI: bat, eza, fd, fzf
- fzf integration: Ctrl-R history, Ctrl-O cd, Ctrl-G repo jump

### Neovim

50+ plugins. Custom colorscheme.

- Bufferline with language-colored labels (GitHub Linguist)
- Inline reference count (symbol-usage)
- One-key Quick Fix / Refactor menu
- Per-language modules (Rust, Go, TypeScript, Python, C++, Kotlin, Terraform, SQL, Lua)

### DB tools: [sabiql](https://github.com/riii111/sabiql)

![sabiql(db tool)](https://github.com/user-attachments/assets/745ab18f-915c-4017-81a6-465c5c5ee11c)

TUI-based DB management tool built with Rust + Ratatui.

- Per-project connection profiles
- Table browser with column/relation preview
- Query editor with syntax highlighting

### lazygit

Delta for modern diffs. `|` key toggles split/unified view.

![lazygit](https://github.com/user-attachments/assets/4312502b-c2a9-4269-86a0-9eeda9671fed)

### AI tooling

main: Codex
sub: Claude Code

`~/.codex/config.toml` is rewritten by the Codex desktop app, so it is `.chezmoiignore`d and not applied. `dot_codex/config.toml.tmpl` is kept only as a hand-maintained reference for base settings; edit the live file directly.

## Trade-offs

- macOS only (AppleScript, pbcopy, etc.)
- Kotlin LSP assumes forked version
