return {
  {
    "tpope/vim-dadbod",
    dependencies = {
      "kristijanhusak/vim-dadbod-ui",
    },
    config = function()
      -- Database UI configuration
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_force_echo_messages = 1
      vim.g.db_ui_win_position = "left"
      vim.g.db_ui_winwidth = 30

      -- Key mappings for SQL development
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          local opts = { buffer = true, silent = true }

          -- Execute query
          vim.keymap.set("n", "<C-e>", "<cmd>DB<cr>", vim.tbl_extend("force", opts, { desc = "Execute SQL query" }))
          vim.keymap.set("v", "<C-e>", ":DB<cr>", vim.tbl_extend("force", opts, { desc = "Execute selected SQL" }))

          -- Database UI toggle
          vim.keymap.set("n", "<leader>db", "<cmd>DBUI<cr>", vim.tbl_extend("force", opts, { desc = "Toggle Database UI" }))

          -- Database operations
          vim.keymap.set("n", "<leader>dbt", "<cmd>DBUIToggle<cr>", vim.tbl_extend("force", opts, { desc = "Toggle DBUI" }))
          vim.keymap.set("n", "<leader>dbf", "<cmd>DBUIFindBuffer<cr>", vim.tbl_extend("force", opts, { desc = "Find DB buffer" }))
          vim.keymap.set("n", "<leader>dbr", "<cmd>DBUIRenameBuffer<cr>", vim.tbl_extend("force", opts, { desc = "Rename DB buffer" }))
          vim.keymap.set("n", "<leader>dbl", "<cmd>DBUILastQueryInfo<cr>", vim.tbl_extend("force", opts, { desc = "Last query info" }))
        end,
      })
    end,
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
  },
  -- SQL LSP configuration
  -- NOTE: Using a wrapper plugin instead of extending "neovim/nvim-lspconfig" directly
  --       because lazy.nvim may skip this config function when lspconfig is already loaded.
  {
    name = "sql-lsp-setup",
    dir = vim.fn.stdpath("config"),
    ft = { "sql", "mysql", "plsql" },
    dependencies = { "neovim/nvim-lspconfig" },
    config = function()
      vim.lsp.config("sqls", {
        cmd = { "sqls" },
        filetypes = { "sql", "mysql", "plsql" },
        root_markers = { ".git", ".sqls.yaml" },
      })
      vim.lsp.enable("sqls")
    end,
  },
}
