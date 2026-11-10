# dotfiles

Personal macOS dotfiles for Kitty, zsh, and Neovim, managed by chezmoi and Nix.

## Setup

Install [Nix](https://nixos.org/download/) and chezmoi, then run:

```bash
chezmoi init --source ~/ghq/github.com/riii111/dotfiles
chezmoi apply
~/bin/dotctl sync-nix-profile
sudo nix run nix-darwin/master#darwin-rebuild -- switch --flake ~/ghq/github.com/riii111/dotfiles#personal
exec zsh
```

Use `#work` instead of `#personal` on the work machine.
After applying Codex hooks, restart Codex and trust them with `/hooks`.

For Claude Code Cloud, see [cloud-setup.sh](scripts/cloud-setup.sh).
For Finder file associations, run [build-open-apps.sh](scripts/build-open-apps.sh) and [setup-default-apps.sh](scripts/setup-default-apps.sh).

## Update

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Nix and Neovim plugin updates arrive as Draft PRs.
Mark one ready for review to run CI, merge it, then apply.
