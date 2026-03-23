# dotfiles

Dev environment for macOS, managed by [chezmoi](https://www.chezmoi.io/).

<img width="720" alt="after-2" src="https://github.com/user-attachments/assets/ab112ea6-e819-46de-9cc1-eb0961824efe" />


## Setup

```bash
# Install chezmoi and apply dotfiles in one command
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply riii111

# Install packages
brew bundle --file ~/ghq/github.com/riii111/dotfiles/Brewfile
```

## Features

### zsh: 9.5ms startup

- Deferred `compinit` after prompt display
- Cache regeneration only on config change
- Modern CLI: bat, eza, fd, fzf
- fzf integration: Ctrl-R history, Ctrl-O cd, Ctrl-G repo jump

```
zsh -i -c exit:  98.5ms → 9.5ms  (-90%)
zsh -il -c exit: 129.7ms → 39.2ms (-70%)
```

### Neovim

50+ plugins, 66ms startup. Custom colorscheme.

- Bufferline with language-colored labels (GitHub Linguist)
- Inline reference count (symbol-usage)
- One-key Quick Fix / Refactor menu
- Per-language modules (Rust, Go, TypeScript, Python, C++, Kotlin, Terraform, SQL, Lua)

### DB tools: [sabiql](https://github.com/riii111/sabiql)

<img width="720" alt="DB Tool - sabiql" src="https://github.com/user-attachments/assets/35cdc1fc-21ee-4446-a8f7-f3d217e3437e" />


TUI-based DB management tool built with Rust + Ratatui.

- Per-project connection profiles
- Table browser with column/relation preview
- Query editor with syntax highlighting

### lazygit

Delta for modern diffs. `|` key toggles split/unified view.

<img width="720" alt="lazygit" src="https://github.com/user-attachments/assets/4312502b-c2a9-4269-86a0-9eeda9671fed" />

### AI tooling

#### Claude Code

- PreToolUse hook: find/grep/cat → fd/rg/bat
- Permission policy: build/test/read-only git auto-allowed, rm requires confirm
- Machine-specific settings via chezmoi template (work/personal)
- Context7 MCP

#### Codex CLI

- GPT-5 custom prompt (skim/focus/dive for inference control)
- `model_reasoning_effort = "high"`
- Context7 MCP

## Trade-offs

- macOS only (AppleScript, pbcopy, etc.)
- Kotlin LSP assumes forked version
