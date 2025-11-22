return {
  -- Treesitter support for Kotlin
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts = opts or {}
      local ensure = opts.ensure_installed or {}
      if not vim.tbl_contains(ensure, "kotlin") then
        table.insert(ensure, "kotlin")
      end
      opts.ensure_installed = ensure
      return opts
    end,
  },

  -- Formatting and linting with ktlint
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = { "kotlin" },
    config = function()
      local null_ls = require("null-ls")

      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.ktlint,
          null_ls.builtins.diagnostics.ktlint,
        },
      })

      -- Auto-format on save
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = { "*.kt", "*.kts" },
        callback = function()
          vim.lsp.buf.format({
            filter = function(client)
              return client.name == "null-ls"
            end,
            timeout_ms = 5000,
          })
        end,
      })

    end,
  },
}
