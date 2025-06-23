return {

  -- Telescope fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-live-grep-args.nvim",
        version = "^1.0.0",
      },
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    },
    opts = function()
      return {
        defaults = {
          file_ignore_patterns = {
            "node_modules/.*",
            "%.git/.*",
            "target/.*",
            "dist/.*",
            "build/.*",
            "%.lock",
            "vendor/.*",
            "%.min%.js",
            "%.min%.css",
          },
          vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case",
            "--trim",
          },
          prompt_prefix = "󰼛 ",
          selection_caret = "󰅂 ",
          layout_config = {
            horizontal = {
              prompt_position = "top",
              preview_width = 0.6,
            },
            width = 0.9,
            height = 0.9,
          },
          sorting_strategy = "ascending",
          winblend = 0,
        },
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
          live_grep_args = {
            auto_quoting = true,
            mappings = {
              i = {
                ["<C-k>"] = require("telescope-live-grep-args.actions").quote_prompt(),
                ["<C-i>"] = require("telescope-live-grep-args.actions").quote_prompt({ postfix = " --iglob " }),
              },
            },
          },
        },
      }
    end,
    config = function(_, opts)
      local telescope = require("telescope")
      telescope.setup(opts)
      telescope.load_extension("fzf")
      telescope.load_extension("live_grep_args")
    end
  },

  -- Statusline
  {
    "nvim-lualine/lualine.nvim",
    opts = function()
      return {
        options = {
          theme = "auto",
          globalstatus = true,
        },
        sections = {
          lualine_c = {
            { "filename", path = 4 }
          }
        }
      }
    end,
  },

  -- Indent guides
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl",
    event = "VeryLazy",
    config = function()
      require("ibl").setup({
        indent = {
          highlight = { "IndentBlanklineChar" },
          char = "│",
        },
        scope = {
          highlight = { "IndentBlanklineContextChar" },
          enabled = true,
        },
      })
    end,
  },

  -- Git signs
  {
    "lewis6991/gitsigns.nvim",
    opts = {},
  },

  -- Terminal
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    opts = function()
      local get_catppuccin_colors = function()
        local has_catppuccin, catppuccin = pcall(require, "catppuccin.palettes")
        if has_catppuccin then
          return catppuccin.get_palette("macchiato")
        else
          return {
            surface0 = "#363a4f",
            surface1 = "#494d64",
            blue = "#8aadf4",
            sky = "#91d7e3",
            mauve = "#c6a0f6",
            text = "#cad3f5",
          }
        end
      end

      local colors = get_catppuccin_colors()

      return {
        size = function(term)
          if term.direction == "horizontal" then
            return 15
          elseif term.direction == "vertical" then
            return vim.o.columns * 0.4
          end
        end,
        open_mapping = [[<c-\>]],
        hide_numbers = true,
        shade_terminals = false,
        start_in_insert = true,
        insert_mappings = true,
        terminal_mappings = true,
        persist_size = true,
        persist_mode = true,
        direction = 'horizontal',
        close_on_exit = true,
        shell = vim.o.shell,
        auto_scroll = true,
        size = 15,
        highlights = {
          Normal = { guibg = "NONE" },
          NormalFloat = { guibg = "NONE" },
          FloatBorder = { guifg = "#00cecb", guibg = "NONE" },
        },
      }
    end,
    config = function(_, opts)
      require("toggleterm").setup(opts)

      local Terminal = require('toggleterm.terminal').Terminal

      -- Horizontal terminal
      local horizontal_term = Terminal:new({
        direction = "horizontal",
        size = 15,
      })

      -- Vertical terminal  
      local vertical_term = Terminal:new({
        direction = "vertical",
        size = function()
          return math.floor(vim.o.columns * 0.4)
        end,
      })

      -- Float terminal (default)
      local float_term = Terminal:new({
        direction = "float",
      })

      -- Key mappings for different layouts
      vim.keymap.set("n", "<Leader>tf", function() float_term:toggle() end, { desc = "Float terminal" })
      vim.keymap.set("n", "<Leader>th", function() horizontal_term:toggle() end, { desc = "Horizontal terminal" })
      vim.keymap.set("n", "<Leader>tv", function() vertical_term:toggle() end, { desc = "Vertical terminal" })

      -- Terminal mode mappings
      function _G.set_terminal_keymaps()
        local opts = {buffer = 0}
        vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], opts)
        vim.keymap.set('t', '<C-h>', [[<Cmd>wincmd h<CR>]], opts)
        vim.keymap.set('t', '<C-j>', [[<Cmd>wincmd j<CR>]], opts)
        vim.keymap.set('t', '<C-k>', [[<Cmd>wincmd k<CR>]], opts)
        vim.keymap.set('t', '<C-l>', [[<Cmd>wincmd l<CR>]], opts)
        vim.keymap.set('t', '<C-w>', [[<C-\><C-n><C-w>]], opts)
      end

      vim.cmd('autocmd! TermOpen term://* lua set_terminal_keymaps()')
    end,
  },

  -- Treesitter context
  {
    "nvim-treesitter/nvim-treesitter-context",
    opts = {}
  },

  -- Glance preview
  {
    "dnlhc/glance.nvim",
    opts = {}
  },

  -- Markview for markdown
  {
    "OXY2DEV/markview.nvim",
    event = { "BufReadPre *.md", "BufNewFile *.md" },
    config = true,
    opts = {},
  },

  -- Discord presence
  "andweeb/presence.nvim",

  -- Search highlighting
  {
    "kevinhwang91/nvim-hlslens",
    event = "VeryLazy",
    config = function()
      require("hlslens").setup({
        calm_down = true,
        nearest_only = true,
        nearest_float_when = "always",
        float_shadow_blend = 0,
        virt_priority = 100,
      })

      local kopts = { noremap = true, silent = true }

      vim.keymap.set("n", "n", [[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.keymap.set("n", "N", [[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.keymap.set("n", "*", [[*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.keymap.set("n", "#", [[#<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.keymap.set("n", "g*", [[g*<Cmd>lua require('hlslens').start()<CR>]], kopts)
      vim.keymap.set("n", "g#", [[g#<Cmd>lua require('hlslens').start()<CR>]], kopts)

      vim.keymap.set("n", "<Esc>", "<Cmd>noh<CR><Cmd>lua require('hlslens').stop()<CR>", kopts)
    end,
  },

  -- Line moving
  {
    "echasnovski/mini.move",
    version = "*",
    event = "VeryLazy",
    config = function()
      require('mini.move').setup()
      vim.keymap.set('v', '<M-Down>', function() require('mini.move').move_selection('down') end)
      vim.keymap.set('v', '<M-Up>', function() require('mini.move').move_selection('up') end)
      vim.keymap.set('n', '<M-Down>', function() require('mini.move').move_line('down') end)
      vim.keymap.set('n', '<M-Up>', function() require('mini.move').move_line('up') end)
    end,
  },
}
