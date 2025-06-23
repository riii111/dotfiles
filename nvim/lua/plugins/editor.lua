return {
  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      ensure_installed = {
        "bash",
        "c",
        "diff",
        "html",
        "javascript",
        "jsdoc",
        "json",
        "jsonc",
        "lua",
        "luadoc",
        "luap",
        "markdown",
        "markdown_inline",
        "python",
        "query",
        "regex",
        "toml",
        "tsx",
        "typescript",
        "vim",
        "vimdoc",
        "yaml",
        "go",
        "gomod",
        "gowork",
        "gosum",
        "rust",
      },
      highlight = { enable = true },
      indent = { enable = true },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
    end,
  },

  -- Treesitter textobjects
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    event = "VeryLazy",
    enabled = true,
    config = function()
      if vim.g.lazy_load_treesitter then
        local plugin = require("lazy.core.config").spec.plugins["nvim-treesitter"]
        require("lazy.core.loader").load(plugin, { event = "VeryLazy" })
      end
    end,
  },

  -- Auto pairs
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    config = function()
      require("nvim-autopairs").setup({
        check_ts = true,
        ts_config = {
          lua = { "string", "source" },
          javascript = { "string", "template_string" },
          java = false,
        },
        disable_filetype = { "TelescopePrompt", "spectre_panel" },
        fast_wrap = {
          map = "<M-e>",
          chars = { "{", "[", "(", '"', "'" },
          pattern = string.gsub([[ [%'%"%)%>%]%)%}%,] ]], "%s+", ""),
          offset = 0,
          end_key = "$",
          keys = "qwertyuiopzxcvbnmasdfghjkl",
          check_comma = true,
          highlight = "PmenuSel",
          highlight_grey = "LineNr",
        },
      })
      
      local npairs = require("nvim-autopairs")
      local Rule = require("nvim-autopairs.rule")
      local cond = require("nvim-autopairs.conds")
      
      npairs.add_rules({
        Rule("$", "$", { "tex", "latex" })
          :with_pair(cond.not_after_regex("%%"))
          :with_pair(cond.not_before_regex("xxx", 3))
          :with_move(cond.none())
          :with_del(cond.not_after_regex("xx"))
          :with_cr(cond.none()),
        Rule("a", "a", "-vim")
      })
    end,
  },

  -- Comment
  {
    "numToStr/Comment.nvim",
    opts = {},
    lazy = false,
  },

  -- Which-key (for key mappings help)
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    opts = {},
  },

  -- Todo comments
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },

  -- Smart splits for window navigation
  {
    "mrjones2014/smart-splits.nvim",
    opts = {},
  },


  -- Better escape
  {
    "max397574/better-escape.nvim",
    enabled = false,
  },

  -- Session management
  {
    "stevearc/resession.nvim",
    opts = {},
  },

  -- UFO folding (disabled to prevent automatic folding)
  {
    "kevinhwang91/nvim-ufo",
    dependencies = "kevinhwang91/promise-async",
    enabled = false,
  },

  -- Guess indent
  {
    "NMAC427/guess-indent.nvim",
    opts = {},
  },

  -- Window picker
  {
    "s1n7ax/nvim-window-picker",
    opts = {},
  },

  -- Snacks (modern UI components)
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      modules = { "explorer", "scratch", "picker" },
      explorer = {
        icons = {
          show = {
            file = true,
            folder = true,
            hidden = true,
            git = true,
          },
          file = {
            default = "󰈔",
          },
          folder = {
            default = "󰉋",
            open = "󰝰",
            empty = "󰉖",
            empty_open = "󰷏",
          },
        },
      },
      picker = {
        ui_select = true,
        layouts = {
          cursor = {
            preview = false,
            layout = {
              backdrop = false,
              row = 1,
              col = 0.3,
              width = 60,
              height = 15,
              min_height = 3,
              border = "rounded",
              title = "{title}",
              title_pos = "center",
              box = "vertical",
              { win = "input", height = 1, border = "bottom" },
              { win = "list", border = "none" },
            },
          },
        },
      },
    },
  },
}