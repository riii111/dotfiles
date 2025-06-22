-- AstroCore-like keymap functionality for compatibility
local function setup_astrocore_keymaps()
  local mappings = {
    n = {
      -- Window splits
      ["<D-Down>"] = { ":split<CR>", desc = "Split window below" },
      ["<D-Right>"] = { ":vsplit<CR>", desc = "Split window right" },
      ["<C-d>"] = { "x", desc = "Forward delete character" },

      -- Search
      ["<C-h>"] = {
        function()
          require("telescope.builtin").live_grep()
        end,
        desc = "Search text in project",
      },
      ["<D-S-f>"] = { 
        function() 
          require("telescope").extensions.live_grep_args.live_grep_args() 
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

      -- Commenting
      ["<D-/>"] = { 
        function() 
          require("Comment.api").toggle.linewise.current() 
        end, 
        desc = "Toggle comment" 
      },

      -- Terminal
      ["<C-S-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal" },

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

      -- Neo-tree toggle
      ["<Leader>o"] = { ":Neotree toggle<CR>", desc = "Toggle file explorer" },
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
    t = {},
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
      -- Setup keymaps after which-key is loaded
      setup_astrocore_keymaps()
    end,
  },
}