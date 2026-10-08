# Agents Guide: Neovim Config Playbook (Language Support + IntelliJ‑like Actions)

## Purpose

- Capture the project’s opinionated patterns so agents can add or maintain language support quickly and consistently.
- Highlight the IntelliJ‑like quick‑fix/refactor flow powered by `lua/utils/lsp-actions.lua`.

## Repo Layout (essentials)

```
.
├── init.lua                   # bootstrap lazy.nvim, import specs
└── lua
    ├── config                 # global options, theme, devicons, colors
    │   ├── options.lua        # vim options, provider/plugin disabling
    │   ├── keymaps.lua        # plugin-independent keymaps (smart editing, etc.)
    │   ├── autocmd.lua        # autocommands (relative number toggle, etc.)
    │   ├── colors.lua
    │   ├── devicons.lua
    │   ├── lazy.lua
    │   └── theme.lua
    ├── plugins                # plugin specs (LSP core, UI, tooling)
    │   ├── keymaps.lua        # plugin-dependent keymaps (Telescope, Oil, etc.)
    │   ├── lsp.lua            # lspconfig, none-ls, cmp, symbol-usage
    │   ├── lspsaga.lua        # LSP-specific keymaps (gd, K, [d, etc.)
    │   ├── mason.lua          # mason + mason-tool-installer
    │   ├── ui.lua             # bufferline, incline, gitsigns, etc.
    │   │                      # (includes plugin-specific keymaps: hlslens, mini.move)
    │   ├── lualine.lua
    │   ├── editor.lua         # treesitter, autopairs, todo-comments, etc.
    │   └── languages          # per-language modules (Treesitter, LSP, keymaps)
    │       ├── cpp.lua
    │       ├── go.lua
    │       ├── rust.lua
    │       ├── python.lua
    │       ├── typescript.lua
    │       └── lua.lua
    └── utils
        └── lsp-actions.lua    # IntelliJ‑like "smart action" menus and refactor helpers
```

## Design Principles

- Keep language logic in its own module under `plugins/languages` (cohesion, low coupling).
- Use Mason for tool bootstrapping; avoid hard‑coded paths (resolve from `vim.fn.stdpath('data') .. '/mason'`).
- Prefer LSP‑native features over duplicating via null‑ls (e.g., clang‑tidy via clangd, not null‑ls).
- Minimal comments: document "why", not "what". Let naming/config tell the story.
- Keymap organization:
  - Plugin-independent keymaps → `config/keymaps.lua` (e.g., smart 0, x without yank)
  - Plugin-dependent keymaps → same file as plugin config or `plugins/keymaps.lua`
  - LSP keymaps → `plugins/lspsaga.lua` (buffer-local, set on LspAttach)

## IntelliJ‑Like Quick Actions

- Entry point: `lua/utils/lsp-actions.lua`
  - Generic: `M.smart_code_action()` and `M.language_specific_code_action()`
  - Language menus: `rust_*`, `go_*`, `python_*`, and `cpp_*` (added)
- Default keymaps (buffer‑local, set in language modules):
  - `<M-CR>` → language‑specific code actions
  - `<D-S-r>` / `<M-S-r>` → language refactor menu
- Extending: add `M.<lang>_quick_actions()` and `M.<lang>_refactor_menu()` then wire them in the new language module.

## New Language Support – Checklist

1) Mason tools
   - Edit `lua/plugins/mason.lua`: add server/formatter to `ensure_installed`.

2) Language module
   - Create `lua/plugins/languages/<lang>.lua` and:
     - Extend Treesitter parser/filetype registration via `utils.treesitter.extend`.
     - Configure LSP with `vim.lsp.config` and `vim.lsp.enable` (root detection via `root_markers`).
     - Register formatters/linters with null‑ls only if the LSP lacks them.
     - Bind `<M-CR>` and refactor menu via `utils.lsp-actions`.

3) UI accents (optional)
   - Bufferline groups can label languages by extension (e.g., `c`, `cpp`, `rs`, `go`, `ts/tsx`, `lua`).
   - Language colors follow GitHub Linguist. Adjust only when readability on the current theme requires it.

4) Validate
   - `:Lazy sync` → `:Mason` shows tools installed.
   - Open a file and verify diagnostics/hover/rename/jump/format.

## Example Skeleton (new `plugins/languages/<lang>.lua`)

lazy.nvim runs only the last `config`/`init` among all specs of the same plugin (just `opts`, `dependencies`, `cmd`, `event`, `ft` and `keys` are merged), so a `config` on the shared `neovim/nvim-lspconfig` spec silently disables the setup of every other language; give each setup its own uniquely named `virtual = true` spec (the check in `tests/nvim/run.lua` fails otherwise).

`config` runs once, for the first buffer of the filetype, so the buffer-local keymaps are set from a `FileType` autocmd, as in `terraform.lua`.

```lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      return require("utils.treesitter").extend(opts, {
        languages = { "<lang>" },
        filetypes = { "<lang>" },
        indent_filetypes = { "<lang>" },
      })
    end,
  },
  {
    "<lang>-lsp-setup",
    virtual = true,
    ft = { "<lang>" },
    dependencies = { "neovim/nvim-lspconfig" },
    config = function()
      vim.lsp.config("<server>", { root_markers = { ".git", "<project files>" } })
      vim.lsp.enable("<server>")
      local ok, actions = pcall(require, "utils.lsp-actions"); if ok then
        vim.api.nvim_create_autocmd("FileType", {
          pattern = { "<lang>" },
          callback = function()
            local opts = { buffer = true, silent = true }
            vim.keymap.set("n", "<M-CR>", actions.language_specific_code_action, opts)
            if actions.<lang>_refactor_menu then
              vim.keymap.set("n", "<D-S-r>", actions.<lang>_refactor_menu, opts)
              vim.keymap.set("n", "<M-S-r>", actions.<lang>_refactor_menu, opts)
            end
          end,
        })
      end
    end,
  },
}
```

## C/C++ Case Notes (2025‑09‑08)

- Added `clangd` with `--clang-tidy`; avoided `null-ls` diagnostics for clang‑tidy to prevent nil lookups and duplication.
- Bufferline items for `c` and `cpp`; colors aligned to GitHub Linguist (C `#555555`, C++ `#F34B7D`).

## Troubleshooting

- No diagnostics? Check server is installed in Mason and buffer `filetype` is correct.
- clang‑tidy: let clangd handle it; do not add `null-ls` diagnostics.
- Format conflicts: ensure only one of LSP or null‑ls formats for the filetype.
- LSP not starting ("No active clients"): If you roll your own `vim.lsp.config/enable`, run config+enable *after* FileType. The safe path is to put config + `vim.lsp.enable` in `ftplugin/<lang>.lua`, or in the `virtual = true` spec with `ft` from the skeleton, which lazy.nvim loads on FileType.

## Do & Don’t

- Do: prefer root detection via `root_markers` in `vim.lsp.config`.
- Do: keep language logic self‑contained in its module.
- Don’t: hard‑code absolute paths or introduce redundant formatters/linters.

## Notable Features of This Neovim Setup

- Modern Completion: `saghen/blink.cmp` with `friendly-snippets`.
- Enhanced LSP UX: `nvimdev/lspsaga.nvim` and `Wansmer/symbol-usage.nvim`.
- Picker and notifications: `folke/snacks.nvim`.
- Project Navigation: `nvim-telescope/telescope.nvim` with `fzf-native` and `live-grep-args`.
- Editor Ergonomics: Treesitter, `windwp/nvim-autopairs`, `folke/which-key.nvim`, and native window resizing.
- Smart Keymaps: Smart 0 (toggle ^ and 0), auto-indent on empty lines (i/A), delete without yank (x/X), visual mode improvements.
- File Management: `stevearc/oil.nvim` (buffered file explorer).
- UI Polish: `akinsho/bufferline.nvim` (language‑grouped labels), `b0o/incline.nvim`, `lukas-reineke/indent-blankline.nvim`, `lewis6991/gitsigns.nvim`, `kevinhwang91/nvim-hlslens`.
- Performance: Lua module loader cache enabled, unused providers/plugins disabled for faster startup.
