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

Manual steps outside this repository:

- Codex: after applying hooks, restart Codex and trust them with `/hooks`.
- Vulnerability monitoring (personal Mac): place the agent at `~/.local/bin/am-i-affected`.
- Finder file associations: run `scripts/build-open-apps.sh`, then `nix shell nixpkgs#duti --command bash scripts/setup-default-apps.sh`. Re-run after a macOS update breaks them.
- Claude Code cloud: set up the environment as the top of [cloud-setup.sh](scripts/cloud-setup.sh) shows.
- Task CLIs for the skills: install `harnexus-crew` with `scripts/install.sh` of [taskctl](https://github.com/riii111/taskctl), `pr-wake` with `scripts/install.sh` of [pr-wake](https://github.com/riii111/pr-wake), and `harnexus` with `bun run install:cli` in the [harnexus](https://github.com/riii111/harnexus) checkout.
- harnexus call socket for harnexus-crew and pr-wake: `~/.zshenv` sets `HARNEXUS_CALL_SOCKET=on`. After `chezmoi apply ~/.zshenv`, quit the app, run `bun run open-app` in the harnexus checkout from a new shell, then check that `launchctl getenv HARNEXUS_CALL_SOCKET` prints `on`.
- Cloud review chats through harnexus-crew: add `harnexus_adapter = "observe"` (or `"write"`) under `[data]` in `~/.config/chezmoi/chezmoi.toml`, run `chezmoi apply`, then restart the app.

### Claude Code Cloud rename

In each Cloud environment's saved setup script, replace `HARNEXUS_TASK=1` with `HARNEXUS_CREW=1` using the command at the top of [cloud-setup.sh](scripts/cloud-setup.sh), then rerun setup. The saved Cloud setting is separate from this repository. A fresh setup rejects the removed enable name rather than installing skills without their CLI.

An existing `~/.cache/cloud-setup/options` from before the rename migrates its enable flag and install prefix once on refresh. Explicit `HARNEXUS_CREW*` settings win, including an empty enable flag. The original options remain in `options.pre-crew`; old executables and task data are not removed. If building crew fails, the existing skills and `task.json` stay until a later successful retry.

A custom cached `TASKCTL_REPO` or nonempty `TASKCTL_REV` requires an explicit corresponding `HARNEXUS_CREW_REPO` or `HARNEXUS_CREW_REV`; set it to an empty value to choose the current default. A cache selecting `TASK_CLI=legacy` requires an explicit `HARNEXUS_CREW=1`. These cases stop before changing the existing setup rather than silently replacing a chosen source.

## Update

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Nix and Neovim plugin updates arrive as Draft PRs. Mark one ready for review to run CI, merge it, then apply.

If C or Rust linking fails with `unknown architecture arm64e.x1`, run `python3 scripts/repair-macos-sdk.py`.
