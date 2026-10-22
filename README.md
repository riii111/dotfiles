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

### Repair a leftover macOS SDK

If C or Rust linking fails with `unknown architecture arm64e.x1`, diagnose the
installed Command Line Tools and SDKs:

```bash
python3 scripts/repair-macos-sdk.py
```

The repair is available only when the default SDK is newer than the installed
Command Line Tools and the installer-selected `MacOSX.sdk` links successfully.
After reviewing the listed candidates, apply it explicitly:

```bash
sudo /usr/bin/python3 scripts/repair-macos-sdk.py --apply
xcrun --kill-cache
```

The script moves the failing SDK and its aliases into the printed backup directory,
then checks default linking. A failed check restores the moved entries. Existing
`SDKROOT` overrides are ignored during diagnosis and remain unchanged; unset a
manual override before checking your normal build. To undo a successful repair,
move the backed-up entries back into `/Library/Developer/CommandLineTools/SDKs/`
with administrator privileges and run `xcrun --kill-cache` again.

## Optional integrations

### Work tools

```bash
~/bin/dotctl work-tools install
~/bin/dotctl work-tools update
```

### GitHub review requests

Notify review requests on macOS and open a Codex chat with the chosen review skill.
See [review-notifier](tools/review-notifier/README.md).

```bash
~/bin/dotctl review-notifier install
```

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
