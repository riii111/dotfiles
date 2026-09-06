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

### Herdr WezTerm status (optional)

Install the release binary at `~/.local/bin/wezterm-git-status-bridge`, then run its `setup --herdr` command. The generated configuration and shell hook use this path; replace the binary in place when updating it.

Herdr needs a one-time plugin link per machine to fire the events that feed the WezTerm right-status git info inside herdr panes.

```bash
herdr plugin link ~/ghq/github.com/riii111/wezterm-git-status-bridge/contrib/herdr-plugin
```

### Finder integration (optional)

Route Finder double-clicks to WezTerm + Neovim / VisiData.

```bash
bash ~/ghq/github.com/riii111/dotfiles/scripts/build-open-apps.sh
bash ~/ghq/github.com/riii111/dotfiles/scripts/setup-default-apps.sh
```

Routing: text / code → Neovim, csv / tsv → csvlens, parquet / sqlite / jsonl → VisiData, images / pdf → Preview (untouched). Re-run both scripts after a macOS update if associations break.

## Nix

Daily CLI tools are managed by the default user Nix profile.

```bash
~/bin/dotctl sync-nix-profile
exec zsh
```

Homebrew stays for GUI / cask packages and is managed by nix-darwin.

### Store maintenance

nix-darwin runs weekly store maintenance for every host: GC deletes profile generations older than 30 days at 03:15 on Sunday, and store optimisation hard-links duplicate files at 04:15 on Sunday. During Nix builds, free space below 30 GiB triggers GC until 50 GiB is available.

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

### Codex Explore router

`bin/executable_codex-explore-router` is a small Python 3.11+ standard-library CLI for Explore tasks. It starts its own `codex app-server --stdio` process and an ephemeral thread; it does not attach to or interrupt Codex Desktop, the normal Codex CLI, or an existing thread.

The router checks `model/list` before starting and uses `thread/start`, `turn/start`, `turn/interrupt`, and `account/usage/read`. Its automatic path is one-way: after a Sol turn passes the threshold and has no pending important tool or child-agent item, it requests one interrupt, waits for that turn's completion event, and starts one Astra turn with `low` effort in the same thread. An interrupt response by itself never starts Astra.

After applying the dotfiles, run an Explore task with the managed skill explicitly:

```sh
codex-explore-router --explore --prompt-file task.md --mode observe
codex-explore-router --explore --prompt-file task.md --mode auto \
  --threshold-seconds 60
```

Modes are `off`, `observe` (the default), and `auto`. `auto` applies only to an explicit Explore skill on a root thread that starts with the configured Sol model, and at most once per run. Natural completion never adds an Astra turn, and a user cancellation never resumes automatically. Use `--mode off` to disable intervention while retaining run logging.

All router settings are CLI arguments; there is no TOML or environment-variable configuration hierarchy. JSONL logs default to `~/.local/state/codex-explore-router/runs.jsonl`; prompts are not written there, while an explicit `--answer-file` can save the final answer. Duration, token usage, and estimated credits are exposed per run for later local measurement; missing usage remains unknown.

### Codex command policy

`dot_codex/rules/default.rules` controls commands that need to run outside the sandbox. Keep `sandbox_workspace_write.network_access = false` in the live `~/.codex/config.toml`; otherwise network commands can run inside the sandbox without consulting these rules.

After `chezmoi apply`, restart Codex and open `/hooks`. Trust and enable the `PreToolUse` and `PermissionRequest` definitions from `~/.codex/hooks.json`. Codex invalidates that trust when a hook definition changes, so repeat this check after updating the hooks.

Verify the live setup with:

```sh
rg -n '^network_access = false$' ~/.codex/config.toml
codex execpolicy check --pretty --rules ~/.codex/rules/default.rules -- gh pr view 1
```

The `PreToolUse` policy reduces accidental direct invocations of recursive `rm` and common destructive Git/GitHub/cloud commands by cooperative agents. It is not a complete enforcement boundary and does not defend against shell indirection, aliases, scripts, interpreters, subprocesses, PATH shadowing, malicious repository code, disabled hooks, or deliberate bypass attempts. Use the sandbox, fixed-purpose wrappers, and repository or platform protections when an operation requires a strong guarantee.

`prompt` rules still apply only to commands that require sandbox escalation; current hooks cannot force an approval prompt for a command already permitted inside the sandbox.

Compared with the previous broad allow list, network-dependent builds, `git pull`, direct `gh api`, and `gh pr checkout` can require approval. This is an intentional trade-off: fixed read-only network commands and dedicated wrappers remain autonomous, while commands with broader execution or mutation paths stop for review.

## Trade-offs

- macOS only (AppleScript, pbcopy, etc.)
- Kotlin LSP assumes forked version
