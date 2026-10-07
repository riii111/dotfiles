# dotfiles

Personal macOS dotfiles for Kitty, zsh, and Neovim, managed by chezmoi and Nix.

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

Use `#work` instead of `#personal` on the work machine.

## Maintenance

CLI tools use the default user Nix profile; GUI apps use Homebrew via nix-darwin.
After updating the Nix packages:

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Nix updates arrive as weekly Draft PRs; Neovim plugin updates arrive monthly.
Review the lockfile diff and commit SHAs, mark **Ready for review** to run CI, then merge and apply manually.
See [AGENTS.md](AGENTS.md) for update procedures.

Use the pinned development tools and run checks with:

```bash
nix develop
nix develop -c ./bin/executable_dotctl test
```

## Optional integrations

### Work tools

```bash
~/bin/dotctl work-tools install
~/bin/dotctl work-tools update
```

### Finder

Open text / code in Neovim, csv / tsv in csvlens, and parquet / sqlite / jsonl in VisiData, all through Kitty.

```bash
bash ~/ghq/github.com/riii111/dotfiles/scripts/build-open-apps.sh
nix shell nixpkgs#duti --command bash ~/ghq/github.com/riii111/dotfiles/scripts/setup-default-apps.sh
```

Re-run both scripts if a macOS update breaks file associations.

## Agent tools

- Edit `~/.codex/config.toml` directly; the [template](dot_codex/config.toml.tmpl) is a reference and is not applied by chezmoi.
- Keep `sandbox_workspace_write.network_access = false` so network commands consult the [command rules](dot_codex/rules/default.rules.tmpl) when they need sandbox escalation.
- After applying or updating hooks, restart Codex and use `/hooks` to trust and enable `PreToolUse` and `PermissionRequest` from `~/.codex/hooks.json`.
- Codex rules apply only to sandbox escalation. Hooks reduce accidental destructive commands but do not provide a complete enforcement boundary.
- In Codex, `fd`, `rg`, and `sed` run inside the sandbox; use `codex-read-lines` to read line ranges outside it.
- In Claude Code, `bun run` stays inside the sandbox because package scripts are agent-editable.

Task launches and reviews use `harnexus-task` from [harnexus](https://github.com/riii111/harnexus).
Install it to `~/.local/bin` with `bun run install:task` from a clean, reviewed checkout of harnexus `origin/main`.

Usage: [task-session-launch](dot_codex/skills/task-session-launch/SKILL.md), [task-review-cycle](dot_codex/skills/task-review-cycle/SKILL.md).
