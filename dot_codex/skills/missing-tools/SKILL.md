---
name: missing-tools
description: |
  Resolves missing CLI tools.
  Use when a command is unavailable, a shell reports command not found,
  or a tool must be run without installing it globally.
---

# Missing Tools

Use this workflow when a command is unavailable in the current shell.

## Priority Order

1. Confirm whether the command is available in the current PATH:

   ```sh
   command -v <command>
   ```

2. Use `nix run` when the nixpkgs package and command are the same entrypoint:

   ```sh
   nix run nixpkgs#<package> -- <args>
   ```

3. Use `nix shell` when a package must provide a command inside a temporary shell:

   ```sh
   nix shell nixpkgs#<package> --command <command> <args>
   ```

4. If the package is unclear, report the missing command and ask before adding
   new dependencies or changing the machine environment.

## Notes

- Never install missing tools globally. Do not use commands such as
  `npm install -g`, `npm i -g`, `pnpm add -g`, `yarn global add`,
  `bun add -g`, `uv tool install`, `brew install`, or language-specific global
  installers to resolve a missing command.
- Prefer adding frequently used tools to the managed dotfiles package set
  instead of repeatedly borrowing them with `nix run` or `nix shell`.
- Use `zsh -lc '<command>'` only when login-shell initialization is required.
