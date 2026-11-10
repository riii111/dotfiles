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

Manual steps:

- Codex: restart Codex after applying hooks, then trust them with `/hooks`.
- Vulnerability monitoring on personal Mac: place the agent at `~/.local/bin/am-i-affected`.
- Finder file associations: run `scripts/build-open-apps.sh`, then `nix shell nixpkgs#duti --command bash scripts/setup-default-apps.sh`.
  Re-run after a macOS update breaks them.
- Claude Code Cloud: follow the setup instructions at the top of [cloud-setup.sh](scripts/cloud-setup.sh).
  If an existing Cloud setup uses `HARNEXUS_TASK=1`, replace it with `HARNEXUS_CREW=1` and rerun setup.
- Task CLIs: install `harnexus-crew` and `pr-wake` using the install scripts in [taskctl](https://github.com/riii111/taskctl) and [pr-wake](https://github.com/riii111/pr-wake).
  Install `harnexus` with `bun run install:cli` in the [harnexus](https://github.com/riii111/harnexus) checkout.
- harnexus call socket: apply `~/.zshenv`, quit the app, and run `bun run open-app` in the harnexus checkout from a new shell.
  Check that `launchctl getenv HARNEXUS_CALL_SOCKET` prints `on`.
- Cloud review chats: add `harnexus_adapter = "observe"` (or `"write"`) under `[data]` in `~/.config/chezmoi/chezmoi.toml`.
  Run `chezmoi apply`, then restart the app.

## Update

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Nix and Neovim plugin updates arrive as Draft PRs.
Mark one ready for review to run CI, merge it, then apply.

If C or Rust linking fails with `unknown architecture arm64e.x1`, run `python3 scripts/repair-macos-sdk.py`.
