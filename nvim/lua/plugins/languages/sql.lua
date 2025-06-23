return {
  -- SQL LSP support
  {
    "sqls-server/sqls",
    build = "go install github.com/sqls-server/sqls@latest",
    ft = { "sql", "mysql", "plsql" },
  },

  -- Database interaction
  {
    "tpope/vim-dadbod",
    dependencies = {
      "kristijanhusak/vim-dadbod-ui",
      "kristijanhusak/vim-dadbod-completion",
    },
    config = function()
      -- Database UI configuration
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_database_icon = 1
      vim.g.db_ui_force_echo_messages = 1
      vim.g.db_ui_win_position = "left"
      vim.g.db_ui_winwidth = 30

      -- Database completion configuration
      vim.g.db_completion_enabled = 1

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

      -- Auto-complete setup for SQL
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sql", "mysql", "plsql" },
        callback = function()
          require("cmp").setup.buffer({
            sources = {
              { name = "vim-dadbod-completion" },
              { name = "buffer" },
            },
          })
        end,
      })
    end,
    cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
  },
}