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
