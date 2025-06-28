
local function setup_keymaps()
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
            default_text = '-g "!**/{node_modules,docs,.git,target,dist,build}/**" ',
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

      -- Meta key aliases for tmux (Cmd keys appear as Meta in tmux)
      ["<M-F>"] = {
        function()
          require("telescope").extensions.live_grep_args.live_grep_args({
            default_text = '-g "!**/{node_modules,docs,.git,target,dist,build}/**" ',
          })
        end,
        desc = "Live Grep with Args (tmux)"
      },
      ["<M-f>"] = {
        function()
          require("telescope.builtin").current_buffer_fuzzy_find()
        end,
        desc = "Find in current buffer (tmux)"
      },
      ["<M-p>"] = {
        function()
          require("telescope.builtin").find_files()
        end,
        desc = "Find files (tmux)"
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
      ["<M-/>"] = {
        function()
          require("Comment.api").toggle.linewise.current()
        end,
        desc = "Toggle comment (tmux)"
      },

      ["<C-S-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal" },
      ["<C-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (tmux compatible)" },
      ["<C-S-2>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (tmux fallback)" },
      ["<F12>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (universal)" },
      ["<Leader>tt"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (leader)" },


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

      -- Oil.nvim file explorer
      ["<Leader>o"] = {
        function()
          require("oil").toggle_float()
        end,
        desc = "Toggle Oil file explorer (float)"
      },
      ["<Leader>E"] = {
        function()
          require("oil").open_float(vim.fn.getcwd())
        end,
        desc = "Open Oil in current working directory"
      },

      -- Cmd key aliases for oil
      ["<D-e>"] = {
        function()
          require("oil").toggle_float()
        end,
        desc = "Toggle Oil file explorer (float)"
      },

      -- Meta key aliases for tmux (all Cmd keys)
      ["<M-Down>"] = { ":split<CR>", desc = "Split window below (tmux)" },
      ["<M-Right>"] = { ":vsplit<CR>", desc = "Split window right (tmux)" },
      ["<M-M-Right>"] = { ":bnext<CR>", desc = "Next buffer (tmux)" },
      ["<M-M-Left>"] = { ":bprevious<CR>", desc = "Previous buffer (tmux)" },
      ["<M-S-v>"] = {
        function()
          vim.cmd("MarkviewOpen")
        end,
        desc = "Markdown preview (tmux)"
      },
      ["<M-e>"] = {
        function()
          require("oil").toggle_float()
        end,
        desc = "Toggle Oil file explorer (float) (tmux)"
      },

      ["<M-CR>"] = {
        function()
          require("utils.lsp-actions").language_specific_code_action()
        end,
        desc = "Code actions"
      },

      -- Git conflict resolution with Diffview
      ["<Leader>gd"] = { ":DiffviewOpen<CR>", desc = "Open diffview" },
      ["<Leader>gc"] = { ":DiffviewClose<CR>", desc = "Close diffview" },
      ["<Leader>gh"] = { ":DiffviewFileHistory<CR>", desc = "File history" },
      ["<Leader>gf"] = { ":DiffviewToggleFiles<CR>", desc = "Toggle file panel" },
      ["<Leader>df"] = { ":lua require('diffview.actions').focus_files()<CR>", desc = "Focus diffview files" },
      ["<Leader>gm"] = { ":DiffviewOpen origin/main...HEAD<CR>", desc = "Compare with main" },

      -- Quick replace shortcuts
      ["<Leader>r"] = { ":%s/<C-r><C-w>//g<Left><Left>", desc = "Replace word under cursor" },
      ["<Leader>R"] = { ":%s//g<Left><Left><Left>", desc = "Replace text (global)" },
    },
    v = {
      -- Commenting
      ["<D-/>"] = {
        "<ESC><CMD>require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>",
        desc = "Toggle comment"
      },
      ["<M-/>"] = {
        "<ESC><CMD>require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>",
        desc = "Toggle comment (tmux)"
      },
      ["<D-c>"] = { '"+y', desc = "Copy to system clipboard" },
      ["<M-c>"] = { '"+y', desc = "Copy to system clipboard (tmux)" },

      -- Indentation
      ["<Tab>"] = { ">gv", desc = "Indent selection" },
      ["<S-Tab>"] = { "<gv", desc = "Unindent selection" },

      -- Visual mode replace
      ["<Leader>r"] = { ":s//g<Left><Left>", desc = "Replace in selection" },
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
      local wk = require("which-key")
      wk.setup({})

      -- Register key groups
      wk.add({
        { "<leader>e", group = "+oil file explorer" },
        { "<leader>E", group = "+oil file explorer" },
        { "<leader>t", group = "+tabs/terminal" },
        { "<leader>w", group = "+window/buffer" },
        { "<leader>r", group = "+replace" },
        { "<leader>R", group = "+replace global" },
        { "<C-g>", group = "+grep/search" },
        { "<C-p>", group = "+files" },
        { "<C-S-f>", group = "+search" },
        { "<C-S-b>", group = "+buffer search" },
        { "<D-f>", group = "+find" },
        { "<D-F>", group = "+grep" },
        { "<D-p>", group = "+files" },
        { "<D-e>", group = "+oil file explorer" },
        { "<D-S-v>", group = "+preview" },
        { "<D-M-Right>", group = "+buffer navigation" },
        { "<D-M-Left>", group = "+buffer navigation" },
        { "<M-f>", group = "+find" },
        { "<M-F>", group = "+grep" },
        { "<M-p>", group = "+files" },
        { "<M-e>", group = "+oil file explorer" },
        { "<M-c>", group = "+clipboard" },
        { "<M-/>", group = "+comment" },
        { "<M-S-v>", group = "+preview" },
        { "<M-CR>", group = "+code action" },
        { "<leader>g", group = "+git diffview" },
        { "<leader>gd", group = "+diffview open" },
        { "<leader>gc", group = "+diffview close" },
        { "<leader>gh", group = "+file history" },
        { "<leader>gf", group = "+toggle files" },
        { "<leader>df", group = "+focus diffview files" },
        { "<leader>gm", group = "+compare main" },
        { "-", group = "+oil parent directory" },
      })

      setup_keymaps()

      -- Global Oil.nvim keymaps
      vim.keymap.set("n", "-", "<CMD>Oil<CR>", { desc = "Open parent directory in Oil" })
    end,
  },
}
