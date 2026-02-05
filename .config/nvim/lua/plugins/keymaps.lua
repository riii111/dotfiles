local function get_visual_selection()
  vim.cmd('normal! "ay')
  return vim.fn.getreg('a'):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function setup_keymaps()
  local mappings = {
    n = {
      -- Window splits (WezTerm: Cmd+Arrow → Ctrl+Shift+Arrow)
      ["<D-Down>"] = { ":split<CR>", desc = "Split window below" },
      ["<D-Right>"] = { ":vsplit<CR>", desc = "Split window right" },
      ["<C-S-Down>"] = { ":split<CR>", desc = "Split window below" },
      ["<C-S-Right>"] = { ":vsplit<CR>", desc = "Split window right" },

      ["<C-g>"] = {
        function()
          require("telescope.builtin").live_grep()
        end,
        desc = "Search text in project",
      },

      -- Resume last telescope search
      ["<M-g>"] = {
        function()
          require("telescope.builtin").resume()
        end,
        desc = "Resume last search",
      },

      ["<D-F>"] = {
        function()
          require("telescope").extensions.live_grep_args.live_grep_args({
            default_text = _G.last_grep_input or "",
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
            default_text = _G.last_grep_input or "",
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

      -- Keymaps
      ["<Leader>?"] = {
        function()
          vim.ui.select(
            { "all", "normal", "insert", "visual", "visual block", "terminal" },
            { prompt = "Keymap mode:" },
            function(choice)
              if choice then
                local mode_map = {
                  all = nil,
                  normal = "n",
                  insert = "i",
                  visual = "v",
                  ["visual block"] = "x",
                  terminal = "t",
                }
                local modes = mode_map[choice] and { mode_map[choice] } or nil
                require("telescope.builtin").keymaps({ modes = modes })
              end
            end
          )
        end,
        desc = "Keymaps (select mode)"
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
      ["<D-k>c"] = {
        function()
          require("Comment.api").toggle.linewise.current()
        end,
        desc = "Add line comment (chord)"
      },

      ["<C-S-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal" },
      ["<C-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (tmux compatible)" },
      ["<C-S-2>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (tmux fallback)" },
      ["<F12>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (universal)" },
      ["<Leader>tt"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (leader)" },


      -- Buffer navigation (WezTerm: Cmd+Opt+Arrow → Alt+Shift+Arrow)
      ["<D-M-Right>"] = { ":bnext<CR>", desc = "Next buffer" },
      ["<D-M-Left>"] = { ":bprevious<CR>", desc = "Previous buffer" },
      ["<M-S-Right>"] = { ":bnext<CR>", desc = "Next buffer" },
      ["<M-S-Left>"] = { ":bprevious<CR>", desc = "Previous buffer" },
      ["<Leader>n"] = {
        function()
          vim.cmd("enew")
          vim.bo.filetype = "markdown"
          vim.cmd("doautocmd FileType markdown")
        end,
        desc = "New markdown note"
      },
      ["<Leader>w"] = { ":bdelete<CR>", desc = "Close buffer" },

      -- Markdown preview
      ["<D-S-v>"] = {
        function()
          vim.cmd("RenderMarkdown toggle")
        end,
        desc = "Markdown preview toggle"
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
      ["<M-M-Right>"] = { ":bnext<CR>", desc = "Next buffer (tmux)" },
      ["<M-M-Left>"] = { ":bprevious<CR>", desc = "Previous buffer (tmux)" },
      ["<M-S-v>"] = {
        function()
          vim.cmd("RenderMarkdown toggle")
        end,
        desc = "Markdown preview toggle (tmux)"
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

      -- Git diff tools
      ["<Leader>gd"] = {
        function()
          local result = vim.fn.system("git diff --quiet")
          if vim.v.shell_error == 0 then
            vim.notify("No local changes", vim.log.levels.INFO)
          else
            vim.notify("Opening difit...", vim.log.levels.INFO)
            -- Use shell pipe: git diff | difit (difit reads from stdin when not TTY)
            vim.fn.jobstart("git diff | difit", {
              cwd = vim.fn.getcwd(),
              detach = true,
            })
          end
        end,
        desc = "Open difit (local diff)"
      },
      ["<Leader>gD"] = {
        function()
          local pr = vim.fn.input("PR number (or Enter for current branch): ")
          local cmd
          if pr == "" then
            cmd = "gh pr diff | delta"
          else
            cmd = "gh pr diff " .. pr .. " | delta"
          end
          vim.cmd("split | terminal " .. cmd)
        end,
        desc = "PR diff with delta"
      },
      ["<Leader>gm"] = {
        function()
          -- Try to get base branch from PR
          local base = vim.fn.system("gh pr view --json baseRefName -q .baseRefName 2>/dev/null"):gsub("%s+", "")
          if base == "" then
            -- No PR, ask user for base branch
            base = vim.fn.input("Base branch (without origin/): ", "main")
            if base == "" then
              return
            end
          end
          -- Use origin/ prefix for remote comparison
          local remote_base = "origin/" .. base
          -- Check if there are differences
          local diff_check = vim.fn.system("git diff --quiet " .. remote_base .. "..HEAD")
          if vim.v.shell_error == 0 then
            vim.notify("No differences with " .. remote_base, vim.log.levels.INFO)
            return
          end
          vim.notify("Comparing with " .. remote_base .. "...", vim.log.levels.INFO)
          -- Use shell pipe: git diff | difit (difit reads from stdin when not TTY)
          vim.fn.jobstart("git diff " .. remote_base .. "..HEAD | difit", {
            cwd = vim.fn.getcwd(),
            detach = true,
          })
        end,
        desc = "Compare with base branch (difit)"
      },

      -- Diffview (file history only)
      ["<Leader>gh"] = { ":DiffviewFileHistory<CR>", desc = "File history" },

      -- Quick replace shortcuts
      ["<Leader>r"] = { ":%s/<C-r><C-w>//g<Left><Left>", desc = "Replace word under cursor" },
      ["<Leader>R"] = { ":%s//g<Left><Left><Left>", desc = "Replace text (global)" },
    },
    x = {
      -- Commenting (use operator 'gc' directly for reliability)
      ["<D-/>"] = {
        function()
          local keys = vim.api.nvim_replace_termcodes('gc', true, false, true)
          vim.api.nvim_feedkeys(keys, 'x', false)
        end,
        desc = "Toggle comment"
      },
      ["<M-/>"] = {
        function()
          local keys = vim.api.nvim_replace_termcodes('gc', true, false, true)
          vim.api.nvim_feedkeys(keys, 'x', false)
        end,
        desc = "Toggle comment (tmux)"
      },
      ["<D-k>c"] = {
        function()
          local keys = vim.api.nvim_replace_termcodes('gc', true, false, true)
          vim.api.nvim_feedkeys(keys, 'x', false)
        end,
        desc = "Add line comment (selection, chord)"
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
    v = {
      ["<D-F>"] = {
        function()
          local selection = get_visual_selection()
          require("telescope").extensions.live_grep_args.live_grep_args({
            default_text = selection,
          })
        end,
        desc = "Live Grep with selection"
      },
      ["<M-F>"] = {
        function()
          local selection = get_visual_selection()
          require("telescope").extensions.live_grep_args.live_grep_args({
            default_text = selection,
          })
        end,
        desc = "Live Grep with selection (tmux)"
      },
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
        { "<leader>?", desc = "+keymaps" },
        { "<leader>e", group = "+oil file explorer" },
        { "<leader>E", group = "+oil file explorer" },
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
        { "<leader>g", group = "+git" },
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

      -- Short command aliases for tmux popup compatibility
      vim.api.nvim_create_user_command('BF', function()
        require('telescope.builtin').current_buffer_fuzzy_find()
      end, { desc = 'Buffer Find (fuzzy)' })
    end,
  },
}
