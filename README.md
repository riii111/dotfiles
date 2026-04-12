# dotfiles

Dev environment for macOS, managed by chezmoi.

![nvim](https://github.com/user-attachments/assets/0511c1be-2d3a-4b09-a14a-10a1e5f715ad)


## Setup

```bash
brew install chezmoi
chezmoi init --source ~/ghq/github.com/riii111/dotfiles
chezmoi apply
brew bundle --file ~/ghq/github.com/riii111/dotfiles/Brewfile
```

### Finder integration (optional)

Route Finder double-clicks to WezTerm + Neovim / VisiData.

```bash
bash ~/ghq/github.com/riii111/dotfiles/scripts/build-open-apps.sh
# Right-click OpenInNvim.app and OpenInVisiData.app in /Applications -> "Open" once to clear Gatekeeper
bash ~/ghq/github.com/riii111/dotfiles/scripts/setup-default-apps.sh
```

Routing: text / code → Neovim, csv / tsv → csvlens, parquet / sqlite / jsonl → VisiData, images / pdf → Preview (untouched).

Markdown clipboard-to-image paste: `<C-v>` in normal mode (uses `pngpaste`, already in Brewfile).

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

## Trade-offs

- macOS only (AppleScript, pbcopy, etc.)
- Kotlin LSP assumes forked version
