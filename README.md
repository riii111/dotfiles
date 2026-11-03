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
- Claude Code cloud: add the command at the top of [cloud-setup.sh](scripts/cloud-setup.sh) to the environment's setup script.

## Update

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Nix and Neovim plugin updates arrive as Draft PRs. Mark one ready for review to run CI, merge it, then apply.

If C or Rust linking fails with `unknown architecture arm64e.x1`, run `python3 scripts/repair-macos-sdk.py`.
