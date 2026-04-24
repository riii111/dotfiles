return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      return require("utils.treesitter").extend(opts, {
        languages = { "nix" },
        filetypes = { "nix" },
        indent_filetypes = { "nix" },
      })
    end,
  },

  {
    name = "nix-lsp-setup",
    dir = vim.fn.stdpath("config") .. "/lua/plugins/languages",
    lazy = false,
    dependencies = {
      "neovim/nvim-lspconfig",
      "nvimtools/none-ls.nvim",
    },
    config = function()
      vim.lsp.config("nixd", {
        cmd = { "nixd" },
        filetypes = { "nix" },
        root_markers = { "flake.nix", ".git" },
        settings = {
          nixd = {
            formatting = {
              command = { "nixfmt" },
            },
          },
        },
      })
      vim.lsp.enable("nixd")

      local null_ls_ok, null_ls = pcall(require, "null-ls")
      if null_ls_ok and not vim.g._nix_null_ls_registered then
        vim.g._nix_null_ls_registered = true
        null_ls.register(null_ls.builtins.formatting.nixfmt)
      end
    end,
  },
}
