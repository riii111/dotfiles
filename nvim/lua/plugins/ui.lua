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
    },
    config = function(_, opts)
      local telescope = require("telescope")
      telescope.setup(opts)
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
    opts = {
      highlights = {
        Normal = { guibg = "NONE" },
        NormalFloat = { guibg = "NONE" },
        FloatBorder = { guifg = "#00cecb", guibg = "NONE" },
      },
      float_opts = {
        border = "curved",
        winblend = 0,
      },
    },
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
      require("hlslens").setup({})
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
