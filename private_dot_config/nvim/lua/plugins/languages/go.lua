return {
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      require("go").setup({
        goimports = "goimports",
        fillstruct = "gopls",
        textobjects = true,
        lsp_cfg = true,
        lsp_inlay_hints = {
          enable = false,
        },
      })

      local lsp_actions = require("utils.lsp-actions")

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "go",
        callback = function()
          local opts = { buffer = true, silent = true }

          vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
          vim.keymap.set("n", "<D-S-r>", lsp_actions.go_refactor_menu, opts)
          vim.keymap.set("n", "<M-S-r>", lsp_actions.go_refactor_menu, opts)
        end,
      })
    end,
    ft = { "go", "gomod" },
    build = ':lua require("go.install").update_all_sync()'
  },
}
