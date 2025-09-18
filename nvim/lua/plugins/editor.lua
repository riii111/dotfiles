return {
  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      sync_install = false,
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
      })
    end,
  },

  -- Comment
  {
    "numToStr/Comment.nvim",
    dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
    opts = function()
      local ok, ts_integ = pcall(require, "ts_context_commentstring.integrations.comment_nvim")
      return {
        pre_hook = ok and ts_integ.create_pre_hook() or nil,
      }
    end,
    lazy = false,
  },

  -- Context-aware commentstring (JSX/TSX 等)
  {
    "JoosepAlviste/nvim-ts-context-commentstring",
    opts = { enable_autocmd = false },
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
      modules = { "scratch", "picker" },
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

  -- Oil.nvim (file explorer that edits filesystem like a buffer)
  {
    "stevearc/oil.nvim",
    lazy = false,
    dependencies = { "echasnovski/mini.icons" },
    opts = {
      -- Take over directory buffers (e.g. `vim .` or `:e src/`)
      default_file_explorer = true,
      
      -- Columns to display
      columns = {
        "icon",
        -- "permissions",
        -- "size", 
        -- "mtime",
      },
      
      -- Buffer-local options for oil buffers
      buf_options = {
        buflisted = false,
        bufhidden = "hide",
      },
      
      -- Window-local options for oil buffers
      win_options = {
        wrap = false,
        signcolumn = "no",
        cursorcolumn = false,
        foldcolumn = "0",
        spell = false,
        list = false,
        conceallevel = 3,
        concealcursor = "nvic",
      },
      
      -- Send deleted files to trash instead of permanently deleting
      delete_to_trash = true,
      
      -- Skip confirmation popup for simple operations
      skip_confirm_for_simple_edits = false,
      
      -- Prompt to save changes before selecting new file
      prompt_save_on_select_new_entry = true,
      
      -- Oil will automatically delete hidden buffers after this delay
      cleanup_delay_ms = 2000,
      
      -- LSP file operations support
      lsp_file_methods = {
        -- Enable LSP file operations
        enabled = true,
        -- Time to wait for LSP file operations to complete
        timeout_ms = 1000,
        -- Autosave buffers that are updated with LSP willRenameFiles
        autosave_changes = true,
      },
      
      -- Set to false to disable default keymaps
      use_default_keymaps = true,
      
      -- Configuration for file view
      view_options = {
        -- Show hidden files and directories by default
        show_hidden = true,
        -- This function defines what is considered a "hidden" file
        is_hidden_file = function(name, bufnr)
          return vim.startswith(name, ".")
        end,
        -- This function defines what will never be shown, even when show_hidden is true
        is_always_hidden = function(name, bufnr)
          return false
        end,
        -- Sort options
        natural_order = true,
        case_insensitive = false,
        sort = {
          { "type", "asc" },
          { "name", "asc" },
        },
      },
      
      -- Configuration for floating window
      float = {
        -- Padding around the floating window
        padding = 2,
        max_width = 0.9,
        max_height = 0.9,
        border = "rounded",
        win_options = {
          winblend = 0,
        },
      },
      
      -- Configuration for preview window
      preview = {
        max_width = 0.9,
        min_width = { 40, 0.4 },
        width = nil,
        max_height = 0.9,
        min_height = { 5, 0.1 },
        height = nil,
        border = "rounded",
        win_options = {
          winblend = 0,
        },
        update_on_cursor_moved = true,
      },
      
      -- Keymaps for oil buffers
      keymaps = {
        ["g?"] = "actions.show_help",
        ["<CR>"] = "actions.select",
        ["<C-s>"] = { "actions.select", opts = { vertical = true }, desc = "Open in vertical split" },
        ["<C-h>"] = { "actions.select", opts = { horizontal = true }, desc = "Open in horizontal split" },
        ["<C-t>"] = { "actions.select", opts = { tab = true }, desc = "Open in new tab" },
        ["<C-p>"] = "actions.preview",
        ["<C-c>"] = { "actions.close", mode = "n" },
        ["<C-l>"] = "actions.refresh",
        ["-"] = { "actions.parent", mode = "n" },
        ["_"] = { "actions.open_cwd", mode = "n" },
        ["`"] = { "actions.cd", mode = "n" },
        ["~"] = { "actions.cd", opts = { scope = "tab" }, mode = "n" },
        ["gs"] = { "actions.change_sort", mode = "n" },
        ["gx"] = "actions.open_external",
        ["g."] = { "actions.toggle_hidden", mode = "n" },
        ["g\\"] = { "actions.toggle_trash", mode = "n" },
        
        -- Custom keymaps for better UX
        ["<Esc>"] = { "actions.close", mode = "n" },
        ["q"] = { "actions.close", mode = "n" },
        ["<C-v>"] = { "actions.select", opts = { vertical = true }, desc = "Open in vertical split" },
      },
    },
  },
}
