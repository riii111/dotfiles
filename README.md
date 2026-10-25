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

Japanese Markdown and skill references can be checked and formatted with
[the Markdown tools](scripts/ai-docs/README.md).

### Repair SDK linking

If C or Rust linking fails with `unknown architecture arm64e.x1`, diagnose it:

```bash
python3 scripts/repair-macos-sdk.py
```

Review the listed SDKs before applying. They are backed up rather than deleted.

```bash
sudo /usr/bin/python3 scripts/repair-macos-sdk.py --apply
xcrun --kill-cache
```

Unset any temporary `SDKROOT` override before retrying your build.

## Optional integrations

### Local vulnerability monitoring

Install the optional agent separately at `~/.local/bin/am-i-affected`.
On the personal Mac, chezmoi installs the wrapper and nix-darwin manages both LaunchAgents automatically.
They collect every three hours and on wake; successful chezmoi, CLI-profile, and nix-darwin applications also request collection.
The wake observer starts at login and restarts only after a crash, with a five-minute throttle.
Diagnostics stay in `~/.am-i-affected-wake.log`; fix setup errors before restarting the observer.
Claude/Codex show cached counts and separate Mac/cloud last-success times.
Restart Codex and trust the updated `SessionStart` handler through `/hooks` to enable its display.
Missing setup is silent; a failed agent cannot fail dotfiles application.
The work Mac receives only the local remediation skill and sends no inventory.
Verify real scheduling, wake collection, status display, transport, and work-Mac application before relying on the integration.

### Work tools

```bash
~/bin/dotctl work-tools install
~/bin/dotctl work-tools update
```

### Review requests and PR watch

[pr-wake](https://github.com/riii111/pr-wake) notifies review requests and runs the harnexus PR watch; set it up as its README shows.
chezmoi writes the PR watch config to `~/.config/harnexus/pr-watch.json` (work machine).
The AI review bot it waits for is `reviewBots` there; to move off CodeRabbit, describe the new bot as the harnexus README shows.

### Finder

Open text / code in Neovim, csv / tsv in csvlens, and parquet / sqlite / jsonl in VisiData, all through Kitty.

```bash
bash ~/ghq/github.com/riii111/dotfiles/scripts/build-open-apps.sh
nix shell nixpkgs#duti --command bash ~/ghq/github.com/riii111/dotfiles/scripts/setup-default-apps.sh
```

Re-run both scripts if a macOS update breaks file associations.

## Codex

- Edit `~/.codex/config.toml` directly; the [template](dot_codex/config.toml.tmpl) is a reference and is not applied by chezmoi.
- Keep `sandbox_workspace_write.network_access = false` so network commands consult the [command rules](dot_codex/rules/default.rules.tmpl) when they need sandbox escalation.
- After applying or updating hooks, restart Codex and use `/hooks` to trust and enable `PreToolUse` and `PermissionRequest` from `~/.codex/hooks.json`.
- Codex rules apply only to sandbox escalation. Hooks reduce accidental destructive commands but do not provide a complete enforcement boundary.

Task launches and reviews use `harnexus-task` from [harnexus](https://github.com/riii111/harnexus).
Install it to `~/.local/bin` with `bun run install:task` from a clean, reviewed checkout of harnexus `origin/main`.

Usage: [task-session-launch](dot_codex/skills/task-session-launch/SKILL.md), [task-review-cycle](dot_codex/skills/task-review-cycle/SKILL.md), [task-dispatch](dot_codex/skills/task-dispatch/README.md).
