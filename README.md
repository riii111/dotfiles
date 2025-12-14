# dotfiles

## Screenshots

### Neovim UI

<img width="1511" height="942" alt="Neovim UI" src="https://github.com/user-attachments/assets/6cf9e4a2-8d24-4547-81f4-d30bff35185a" />

### IntelliJ-like actions (Quick Fix / Refactor flow)

<img width="1013" height="196" alt="IntelliJ-like actions" src="https://github.com/user-attachments/assets/da51445c-1d46-4980-a469-fc094a2ba3f8" />

### dbn / dbx (DB Client)

<img width="1507" height="948" alt="dbn / dbx" src="https://github.com/user-attachments/assets/e69b298b-e0bb-4d87-a9da-fe0e1641af37" />

## Overview

This repository contains my personal dotfiles, focused on a fast and consistent development experience on macOS:

- Neovim: IntelliJ-like actions + a modern, cohesive UI
- DB workflow: project-local DSN + one-command DB access (`dbx`, `dbn`)
- Terminal workflow: one-command “editor + AI + shell” environment (`ghodev`, `tmux-dev`)
- Git workflow: readable diffs and fzf-powered interactive helpers

## Highlights

### Neovim: IntelliJ-like actions + modern UI

This Neovim setup aims to feel “IDE-like” while keeping the editor fast and scriptable.

- IntelliJ-like actions: a single “smart actions” entry point that routes to language-appropriate quick fixes and refactors (and can auto-apply obvious actions when it makes sense).
- Smooth scrolling: tuned via `neoscroll.nvim` for a modern, less jarring feel.
- Custom look & feel: a highlight-based theme (not just a stock colorscheme) is applied consistently and re-applied on colorscheme changes.
- UI polish: language-colored buffer grouping, fuzzy finder UX, inline file context, git UI, and terminal integrations are tuned as a cohesive set rather than piecemeal defaults.

See: `nvim/lua/utils/lsp-actions.lua`, `nvim/lua/plugins/languages/`, `nvim/lua/plugins/neoscroll.lua`, `nvim/lua/config/theme.lua`, `nvim/lua/plugins/ui.lua`

### Kotlin: tuned for generated code navigation

Kotlin is set up with a forked `kotlin-language-server` workflow to improve definition jumps in generated code bases.
This is a deliberate trade-off for Kotlin-heavy projects.

See: `nvim/lua/plugins/languages/kotlin.lua`

### DB tools: `dbx` and `dbn`

Two small scripts optimize day-to-day DB work:

- `dbx`: opens an interactive DB client (`pgcli` / `mycli`) using DSN from a project-local config file, with per-project history
- `dbn`: table navigator with previews (columns and relations) and a quick path to copy a query template to clipboard

They support Postgres and MySQL/MariaDB.

See: `bin/dbx`, `bin/dbn`

### One-command dev environment

- `ghodev`: starts Ghostty, splits panes, and launches “editor + AI CLI” automatically
- `tmux-dev`: creates (or attaches to) a project-scoped tmux session with an editor and AI CLI pane

See: `bin/ghodev`, `bin/tmux-dev`

### Zsh: fast startup

Zsh is configured as a small “dev UX layer”:

- Startup caching: generates an init cache under the XDG cache dir and only re-runs slow init when `.zshrc` changes
- XDG + PATH discipline: keeps caches/state organized and avoids PATH duplication
- Editor-first: shells, git, and man pages are centered around Neovim
- Interactive UX: tuned `fd`/`fzf` navigation with previews, plus completions and autosuggestions
- Dev helpers: shortcuts for common workflows (Rust tests, Docker, Git hooks)

See: `.zshrc`

### Git UX: readable diffs and interactive helpers

- `delta` is used for clean, readable diffs (also tuned to work well with lazygit/tcell rendering)
- fzf-powered aliases provide a GUI-like staging and history browsing flow

See: `.gitconfig`, `lazygit/config.yml`

### Git hook templates

There is a helper to install per-repo pre-commit hooks from templates (language-specific formatting/linting, with macOS notifications).

See: `.git-hooks.zsh`, `.git_hook_templates/`

### Search tuned for AI tools

Ripgrep defaults are tuned for AI-assisted code browsing (JSON output, size limits, ignore defaults).

See: `.ripgreprc`, `.rgignore`

### AI tooling (Claude Code / Codex CLI)

This repo also includes configuration for AI coding tools, with an emphasis on repeatable “search → inspect → change” loops.

#### Claude Code

- Sets environment defaults so search/log output is predictable (e.g. ripgrep config path, telemetry off, git lock behavior).
- Uses a pre-tool hook to steer searches toward low-noise, structured tools (e.g. blocks `find`/`grep`/`cat` in favor of `fd`/`rg`/`bat`).
- Ships reusable command recipes for common “check” workflows under `.claude/commands/` (e.g. rust checks, full-stack checks).
- Uses an explicit allow/deny permission policy with “ask” gates for destructive operations.
- Custom status line integrates CLI usage telemetry (via `ccusage`) for day-to-day runs.

See: `.claude/settings.json`, `.claude/commands/`

#### Codex CLI

- Enables higher-reasoning mode and streamable shell UX.
- Prewires MCP servers for code navigation and documentation lookup (e.g. Context7, and AWS documentation tooling).
- Web-search request is enabled to support “latest” lookups when needed.

See: `.codex/config.toml`, `.codex/AGENTS.md`

## Setup (minimal)

### Install dependencies (recommended)

This repo contains a `Brewfile`. If you use Homebrew Bundle:

```bash
brew bundle --file Brewfile
```

### Add `~/bin` to PATH

If you want to use scripts under `bin/` easily, ensure your shell includes `~/bin` in `PATH`.

### Optional: ripgrep defaults for AI tooling

If you want the same search defaults used by the AI configs:

- Place `.ripgreprc` at `~/.ripgreprc`
- Place `.rgignore` at `~/.rgignore`

### DB config (`.dbx.toml`)

Place `.dbx.toml` at the project root (do not commit credentials).

Example:

```toml
default = "app_ro"

[profiles.app_ro]
dsn = "postgres://app_ro:app_ro@127.0.0.1:5432/app?sslmode=disable"

[profiles.app_rw]
dsn = "postgres://app:app@127.0.0.1:5432/app?sslmode=disable"
```

Then:

- Run `dbx` to open an interactive client
- Run `dbn` to browse tables and copy query templates

## Trade-offs

- macOS-oriented: some scripts assume macOS tools (e.g. AppleScript, clipboard utilities) and Ghostty.
- Kotlin setup assumes a locally built / forked `kotlin-language-server` for better navigation in some codebases.
- `dbx` / `dbn` assume several CLI dependencies (fzf, yq, pgcli/mycli, pspg, etc.). Use `Brewfile` as a reference.
