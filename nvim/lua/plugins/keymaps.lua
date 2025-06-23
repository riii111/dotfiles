local function setup_unified_keymaps()
  local function setup_cmd_meta_alias()
    if vim.env.TMUX then
      vim.keymap.set("n", "<M-F>", function() require("telescope").extensions.live_grep_args.live_grep_args() end, { desc = "Live Grep with Args" })
      vim.keymap.set("n", "<M-f>", function() require("telescope.builtin").current_buffer_fuzzy_find() end, { desc = "Find in current buffer" })
      vim.keymap.set("n", "<M-p>", function() require("telescope.builtin").find_files() end, { desc = "Find files" })
      vim.keymap.set("n", "<M-S-v>", function() vim.cmd("MarkviewOpen") end, { desc = "Markdown preview" })
      vim.keymap.set("n", "<M-/>", function() require("Comment.api").toggle.linewise.current() end, { desc = "Toggle comment" })
      vim.keymap.set("v", "<M-/>", "<ESC><CMD>require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>", { desc = "Toggle comment" })
      vim.keymap.set("v", "<M-c>", '"+y', { desc = "Copy to system clipboard" })
    end
  end

  setup_cmd_meta_alias()
end

local function setup_astrocore_keymaps()
  local mappings = {
    n = {
      -- Window splits
      ["<D-Down>"] = { ":split<CR>", desc = "Split window below" },
      ["<D-Right>"] = { ":vsplit<CR>", desc = "Split window right" },
      ["<C-d>"] = { "x", desc = "Forward delete character" },

      ["<C-g>"] = {
        function()
          require("telescope.builtin").live_grep()
        end,
        desc = "Search text in project",
      },

      ["<D-F>"] = {
        function()
          require("telescope").extensions.live_grep_args.live_grep_args({
            default_text = '-g "!node_modules/**" -g "!.git/**" -g "!target/**" -g "!dist/**" -g "!build/**" ',
          })
        end,
        desc = "Live Grep with Args"
      },
      ["<D-f>"] = {
        function()
          require("telescope.builtin").current_buffer_fuzzy_find()
        end,
        desc = "Find in current buffer"
      },
      ["<D-p>"] = {
        function()
          require("telescope.builtin").find_files()
        end,
        desc = "Find files"
      },

      -- Reliable keymaps that work in both tmux and non-tmux environments  
      ["<C-p>"] = {
        function()
          require("telescope.builtin").find_files()
        end,
        desc = "Find files (universal)"
      },
      ["<C-S-f>"] = {
        function()
          require("telescope").extensions.live_grep_args.live_grep_args()
        end,
        desc = "Live Grep (universal)"
      },
      ["<C-S-b>"] = {
        function()
          require("telescope.builtin").current_buffer_fuzzy_find()
        end,
        desc = "Find in buffer (universal)"
      },

      -- Commenting
      ["<D-/>"] = {
        function()
          require("Comment.api").toggle.linewise.current()
        end,
        desc = "Toggle comment"
      },

      ["<C-S-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal" },
      ["<C-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (tmux compatible)" },
      ["<C-S-2>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (tmux fallback)" },
      ["<F12>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (universal)" },
      ["<Leader>tt"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (leader)" },

      -- Test mapping
      ["<Leader>xx"] = { ":echo 'Leader xx pressed!'<CR>", desc = "Test Leader mapping" },

      -- Buffer operations
      ["<D-M-Right>"] = { ":bnext<CR>", desc = "Next buffer" },
      ["<D-M-Left>"] = { ":bprevious<CR>", desc = "Previous buffer" },
      ["<Leader>t"] = { ":enew<CR>", desc = "New buffer" },
      ["<Leader>w"] = { ":bdelete<CR>", desc = "Close buffer" },

      -- Markdown preview
      ["<D-S-v>"] = {
        function()
          vim.cmd("MarkviewOpen")
        end,
        desc = "Markdown preview"
      },

      -- Snacks explorer navigation
      ["<Leader>o"] = {
        function()
          if vim.bo.filetype == "snacks_explorer" then
            vim.cmd("wincmd p")
          else
            vim.cmd("wincmd w")
          end
        end,
        desc = "Switch between explorer and buffer"
      },
      ["<Leader>e"] = {
        function()
          Snacks.explorer()
        end,
        desc = "Toggle explorer visibility"
      },

      ["<M-CR>"] = {
        function()
          require("utils.lsp-actions").language_specific_code_action()
        end,
        desc = "Code actions"
      },
    },
    v = {
      -- Commenting
      ["<D-/>"] = {
        "<ESC><CMD>require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>",
        desc = "Toggle comment"
      },
      ["<D-c>"] = { '"+y', desc = "Copy to system clipboard" },

      -- Indentation
      ["<Tab>"] = { ">gv", desc = "Indent selection" },
      ["<S-Tab>"] = { "<gv", desc = "Unindent selection" },
    },
    i = {
      -- Buffer operations
      ["<C-Tab>"] = { "<Esc>:bnext<CR>a", desc = "Next buffer" },
      ["<C-S-Tab>"] = { "<Esc>:bprevious<CR>a", desc = "Previous buffer" },
      ["<C-d>"] = { "<Del>", desc = "Forward delete character" },

      -- Indentation
      ["<S-Tab>"] = { "<C-d>", desc = "Unindent line" },
    },
    t = {
      ["<C-S-@>"] = { "<C-\\><C-n>:ToggleTerm<CR>", desc = "Toggle terminal from terminal" },
      ["<C-S-2>"] = { "<C-\\><C-n>:ToggleTerm<CR>", desc = "Toggle terminal from terminal (tmux)" },
      ["<F12>"] = { "<C-\\><C-n>:ToggleTerm<CR>", desc = "Toggle terminal from terminal (fallback)" },
    },
  }

  -- Apply keymaps
  for mode, mode_mappings in pairs(mappings) do
    for lhs, mapping in pairs(mode_mappings) do
      local rhs = mapping[1]
      local opts = { desc = mapping.desc, silent = true }

      if type(rhs) == "function" then
        vim.keymap.set(mode, lhs, rhs, opts)
      else
        vim.keymap.set(mode, lhs, rhs, opts)
      end
    end
  end
end

return {
  -- This plugin just sets up the keymaps
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    config = function()
      require("which-key").setup({})
      setup_astrocore_keymaps()
      setup_unified_keymaps()
    end,
  },
}
