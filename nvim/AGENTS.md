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
    │   ├── lsp.lua            # lspconfig, none-ls, cmp, DAP, symbol-usage
    │   ├── lspsaga.lua        # LSP-specific keymaps (gd, K, [d, etc.)
    │   ├── mason.lua          # mason + mason-tool-installer
    │   ├── ui.lua             # bufferline, incline, gitsigns, diffview, etc.
    │   │                      # (includes plugin-specific keymaps: hlslens, mini.move)
    │   ├── lualine.lua
    │   ├── editor.lua         # treesitter, textobjects, autopairs, comment, etc.
    │   ├── noice.lua          # noice + notify
    │   ├── dial.lua           # dial.nvim (increment/decrement)
    │   └── languages          # per-language modules (Treesitter, LSP, DAP, keymaps)
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
   - Edit `lua/plugins/mason.lua`: add server/formatter/debugger to `ensure_installed`.

2) Language module
   - Create `lua/plugins/languages/<lang>.lua` and:
     - Extend Treesitter parsers via `opts.ensure_installed`.
     - Configure LSP with `lspconfig` (root detection via `lspconfig.util.root_pattern`).
     - Register formatters/linters with null‑ls only if the LSP lacks them.
     - Add DAP adapter (optional) resolved from Mason.
     - Bind `<M-CR>` and refactor menu via `utils.lsp-actions`.

3) UI accents (optional)
   - Bufferline groups can label languages by extension (e.g., `c`, `cpp`, `rs`, `go`, `ts/tsx`, `lua`).
   - Language colors follow GitHub Linguist. Adjust only when readability on the current theme requires it.

4) Validate
   - `:Lazy sync` → `:Mason` shows tools installed.
   - Open a file and verify diagnostics/hover/rename/jump/format.
   - If DAP added: `:lua require('dap').continue()` boots with the adapter.

## Example Skeleton (new `plugins/languages/<lang>.lua`)

```lua
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts = opts or {}
      local ensure = opts.ensure_installed or {}
      for _, lang in ipairs({ "<lang>" }) do
        if not vim.tbl_contains(ensure, lang) then table.insert(ensure, lang) end
      end
      opts.ensure_installed = ensure
      return opts
    end,
  },
  {
    "neovim/nvim-lspconfig",
    ft = { "<lang>" },
    config = function()
      local lspconfig = require("lspconfig")
      local util = lspconfig.util
      lspconfig.<server>.setup({ root_dir = util.root_pattern(".git", "<project files>") })
      local ok, actions = pcall(require, "utils.lsp-actions"); if ok then
        local opts = { buffer = true, silent = true }
        vim.keymap.set("n", "<M-CR>", actions.language_specific_code_action, opts)
        if actions.<lang>_refactor_menu then
          vim.keymap.set("n", "<D-S-r>", actions.<lang>_refactor_menu, opts)
          vim.keymap.set("n", "<M-S-r>", actions.<lang>_refactor_menu, opts)
        end
      end
    end,
  },
}
```

## C/C++ Case Notes (2025‑09‑08)

- Added `clangd` with `--clang-tidy`; avoided `null-ls` diagnostics for clang‑tidy to prevent nil lookups and duplication.
- DAP via `codelldb` from Mason; server adapter resolved from Mason `bin`.
- Bufferline items for `c` and `cpp`; colors aligned to GitHub Linguist (C `#555555`, C++ `#F34B7D`).

## Troubleshooting

- No diagnostics? Check server is installed in Mason and buffer `filetype` is correct.
- clang‑tidy: let clangd handle it; do not add `null-ls` diagnostics.
- Format conflicts: ensure only one of LSP or null‑ls formats for the filetype.
- DAP not launching: verify adapter path under Mason and that the executable exists.
- LSP not starting ("No active clients"): If you roll your own `vim.lsp.config/enable`, run config+enable *after* FileType. The safe path is to put config + `vim.lsp.enable` in `ftplugin/<lang>.lua`, or just use `lspconfig.setup` which already wires FileType autostart.

## Do & Don’t

- Do: prefer root detection via `lspconfig.util.root_pattern`.
- Do: keep language logic self‑contained in its module.
- Don’t: hard‑code absolute paths or introduce redundant formatters/linters.

## Notable Features of This Neovim Setup

- Modern Completion: `saghen/blink.cmp` with `friendly-snippets`.
- Enhanced LSP UX: `nvimdev/lspsaga.nvim` and `Wansmer/symbol-usage.nvim`.
- Rich Command UI: `folke/noice.nvim` + `rcarriga/nvim-notify`.
- Project Navigation: `nvim-telescope/telescope.nvim` with `fzf-native` and `live-grep-args`.
- Editor Ergonomics: Treesitter + textobjects, `windwp/nvim-autopairs`, `numToStr/Comment.nvim`, `folke/which-key.nvim`, `NMAC427/guess-indent.nvim`, `max397574/better-escape.nvim`, `mrjones2014/smart-splits.nvim`.
- Smart Keymaps: Smart 0 (toggle ^ and 0), auto-indent on empty lines (i/A), delete without yank (x/X), visual mode improvements.
- Smart Editing: `monaqa/dial.nvim` (increment dates, booleans, case conversion).
- File Management: `stevearc/oil.nvim` (buffered file explorer), session management via `resession.nvim`.
- UI Polish: `akinsho/bufferline.nvim` (language‑grouped labels), `b0o/incline.nvim`, `lukas-reineke/indent-blankline.nvim`, `lewis6991/gitsigns.nvim`, `sindrets/diffview.nvim`, `akinsho/toggleterm.nvim`, `kevinhwang91/nvim-hlslens`.
- Debugging: `mfussenegger/nvim-dap` + `rcarriga/nvim-dap-ui`; language adapters configured per module (e.g., C/C++ with `codelldb`).
- Performance: Lua module loader cache enabled, unused providers/plugins disabled for faster startup.
