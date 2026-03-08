# dotfiles

Dev environment for macOS.

<img width="720" alt="Neovim UI" src="https://github.com/user-attachments/assets/08e4577c-8885-4476-a1ec-9a62b2c00b60" />

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

<img width="600" alt="Quick Fix / Refactor" src="https://github.com/user-attachments/assets/da51445c-1d46-4980-a469-fc094a2ba3f8" />

### DB tools: [sabiql](https://github.com/riii111/sabiql)

TUI-based DB management tool built with Rust + Ratatui.

- Per-project connection profiles
- Table browser with column/relation preview
- Query editor with syntax highlighting

### lazygit

Delta for modern diffs. `|` key toggles split/unified view.
<img width="720" alt="lazygit" src="https://github.com/user-attachments/assets/8669819b-945f-43d3-b030-0ae668032efd" />

### AI tooling

#### Claude Code

- PreToolUse hook: find/grep/cat → fd/rg/bat
- Permission policy: build/test/read-only git auto-allowed, rm requires confirm
- Command recipes: `/rust-check`, `/full-check`, etc.
- Context7 MCP

#### Codex CLI

- GPT-5 custom prompt (skim/focus/dive for inference control)
- `model_reasoning_effort = "high"`
- Context7 MCP

## Setup

### Install dependencies

```bash
brew bundle --file Brewfile
```

### PATH

Add `~/bin` to PATH for scripts in `bin/`.

## Trade-offs

- macOS only (AppleScript, pbcopy, etc.)
- Kotlin LSP assumes forked version
