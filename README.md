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
- Task CLIs for the skills: install `taskctl` with `scripts/install.sh --compat` of [taskctl](https://github.com/riii111/taskctl), `pr-wake` with `scripts/install.sh` of [pr-wake](https://github.com/riii111/pr-wake), and `harnexus` with `bun run install:cli` in the [harnexus](https://github.com/riii111/harnexus) checkout. The skills fall back to `harnexus-task` while `taskctl` is missing.
- harnexus call socket for taskctl and pr-wake: `~/.zshenv` sets `HARNEXUS_CALL_SOCKET=on`. After `chezmoi apply ~/.zshenv`, quit the app, run `bun run open-app` in the harnexus checkout from a new shell, then check that `launchctl getenv HARNEXUS_CALL_SOCKET` prints `on`.
- Cloud review chats through taskctl: add `harnexus_adapter = "observe"` (or `"write"`) under `[data]` in `~/.config/chezmoi/chezmoi.toml`, run `chezmoi apply`, then restart the app.

## Update

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Nix and Neovim plugin updates arrive as Draft PRs. Mark one ready for review to run CI, merge it, then apply.

If C or Rust linking fails with `unknown architecture arm64e.x1`, run `python3 scripts/repair-macos-sdk.py`.
