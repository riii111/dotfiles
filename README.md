# dotfiles

Dev environment for macOS.

<img width="720" alt="Neovim UI" src="https://github.com/user-attachments/assets/6cf9e4a2-8d24-4547-81f4-d30bff35185a" />

## Features

### zsh: 9.5ms startup

- Deferred `compinit` after prompt display
- Cache regeneration only on config change
- Modern CLI: bat, eza, fd, fzf
- fzf integration: Ctrl-R history, Ctrl-O cd, `cghq` repo jump

```
zsh -i -c exit:  98.5ms → 9.5ms  (-90%)
zsh -il -c exit: 129.7ms → 39.2ms (-70%)
```

### Neovim

50+ plugins, 66ms startup. Custom colorscheme.

- Bufferline with language-colored labels (GitHub Linguist)
- Inline reference count (symbol-usage)
- One-key Quick Fix / Refactor menu
- Per-language modules (Rust, Go, TypeScript, Python, C++)

<img width="600" alt="Quick Fix / Refactor" src="https://github.com/user-attachments/assets/da51445c-1d46-4980-a469-fc094a2ba3f8" />

### DB tools: dbx / dbn

Per-project DB connection management.

- `dbx`: opens pgcli/mycli with per-project history
- `dbn`: table browser with column/relation preview, copy query template

<img width="720" alt="dbn / dbx" src="https://github.com/user-attachments/assets/e69b298b-e0bb-4d87-a9da-fe0e1641af37" />

Config: place `.dbx.toml` at project root (do not commit):

```toml
default = "app_ro"

[profiles.app_ro]
dsn = "postgres://user:pass@127.0.0.1:5432/app?sslmode=disable"
```

### lazygit

Delta for modern diffs. `|` key toggles split/unified view.
<img width="720" alt="dbn / dbx" src="https://github.com/user-attachments/assets/de6196b9-89a1-458c-b46a-0c869e1c091f" />

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
- dbx/dbn require fzf, yq, pgcli/mycli, pspg, etc.
