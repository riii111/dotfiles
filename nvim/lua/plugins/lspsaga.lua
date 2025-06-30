return {
  -- lspsaga for enhanced LSP UI
  {
    "nvimdev/lspsaga.nvim",
    enabled = true,
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    config = function()
      require("lspsaga").setup({
        ui = {
          border = "rounded",
          devicon = true,
          title = true,
          winblend = 10,
          expand = "",
          collapse = "",
          code_action = "💡",
          incoming = "📥 ",
          outgoing = "📤 ",
        },
        hover = {
          max_width = 0.6,
          max_height = 0.8,
          open_link = "gx",
          open_browser = "!open",
        },
        diagnostic = {
          show_code_action = true,
          show_source = true,
          jump_num_shortcut = true,
          max_width = 0.7,
          max_height = 0.6,
          text_hl_follow = true,
          border_follow = true,
          keys = {
            exec_action = "o",
            quit = "q",
            toggle_or_jump = "<CR>",
            quit_in_show = { "q", "<ESC>" },
          },
        },
        definition = {
          width = 0.6,
          height = 0.5,
          save_pos = false,
          keys = {
            edit = "<C-c>o",
            vsplit = "<C-c>v",
            split = "<C-c>s",
            tabe = "<C-c>t",
            quit = "q",
            close = "<ESC>",
          },
        },
        code_action = {
          num_shortcut = true,
          show_server_name = false,
          extend_gitsigns = true,
          keys = {
            quit = "q",
            exec = "<CR>",
          },
        },
        lightbulb = {
          enable = true,
          sign = true,
          virtual_text = false,
          debounce = 10,
          sign_priority = 40,
        },
        rename = {
          in_select = false,
          auto_save = false,
          project_max_width = 0.5,
          project_max_height = 0.5,
          keys = {
            quit = "<C-c>",
            exec = "<CR>",
            select = "x",
          },
        },
        symbol_in_winbar = {
          enable = false,  -- シンボル表示を無効化
        },
        outline = {
          enable = false,  -- アウトライン機能を無効化
        },
        beacon = {
          enable = true,
          frequency = 7,
        },
      })
      
      -- キーマップの設定
      local opts = { noremap = true, silent = true }
      
      -- Definition Preview (条件付きで設定)
      local function setup_lsp_keymaps()
        local clients = vim.lsp.get_clients({ bufnr = 0 })
        if #clients > 0 then
          vim.keymap.set("n", "gp", "<cmd>Lspsaga peek_definition<CR>", vim.tbl_extend("force", opts, { desc = "Peek Definition", buffer = true }))
          vim.keymap.set("n", "gt", "<cmd>Lspsaga peek_type_definition<CR>", vim.tbl_extend("force", opts, { desc = "Peek Type Definition", buffer = true }))
        end
      end
      
      -- LSPアタッチ時にキーマップを設定
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(event)
          setup_lsp_keymaps()
        end,
      })
      
      -- Enhanced Hover 
      vim.keymap.set("n", "K", "<cmd>Lspsaga hover_doc<CR>", vim.tbl_extend("force", opts, { desc = "Hover Documentation" }))
      
      -- Enhanced Diagnostics Navigation
      vim.keymap.set("n", "[d", "<cmd>Lspsaga diagnostic_jump_prev<CR>", vim.tbl_extend("force", opts, { desc = "Previous Diagnostic" }))
      vim.keymap.set("n", "]d", "<cmd>Lspsaga diagnostic_jump_next<CR>", vim.tbl_extend("force", opts, { desc = "Next Diagnostic" }))
      vim.keymap.set("n", "<leader>d", "<cmd>Lspsaga show_line_diagnostics<CR>", vim.tbl_extend("force", opts, { desc = "Show Line Diagnostics" }))
      vim.keymap.set("n", "<leader>D", "<cmd>Lspsaga show_cursor_diagnostics<CR>", vim.tbl_extend("force", opts, { desc = "Show Cursor Diagnostics" }))
      
      -- Call Hierarchy
      vim.keymap.set("n", "<leader>ci", "<cmd>Lspsaga incoming_calls<CR>", vim.tbl_extend("force", opts, { desc = "Incoming Calls" }))
      vim.keymap.set("n", "<leader>co", "<cmd>Lspsaga outgoing_calls<CR>", vim.tbl_extend("force", opts, { desc = "Outgoing Calls" }))
      
      -- Enhanced Rename 
      vim.keymap.set("n", "<leader>rn", "<cmd>Lspsaga rename<CR>", vim.tbl_extend("force", opts, { desc = "LSP Saga Rename" }))
    end,
    event = "VeryLazy",
  },
}
