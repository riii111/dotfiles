-- You can also add or configure plugins by creating files in this `plugins/` folder
-- PLEASE REMOVE THE EXAMPLES YOU HAVE NO INTEREST IN BEFORE ENABLING THIS FILE
-- Here are some examples:

---@type LazySpec
return {
  -- Forcefully add Telescope if missing from core load
  { "nvim-telescope/telescope.nvim",
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

  { "nvim-treesitter/nvim-treesitter-context", opts = {} },
  { "dnlhc/glance.nvim", opts = {} },
  { "OXY2DEV/markview.nvim",
    event = { "BufReadPre *.md", "BufNewFile *.md" },
    config = true,
    opts = {},
  },

  -- Add nvim-hlslens for search count display
  {
    "kevinhwang91/nvim-hlslens",
    event = "VeryLazy",
    config = function()
      require("hlslens").setup({})
      
      -- Integrate with vim-visual-multi (which is already present)
      local vm_hlslens_integration = function()
        local success, hlslens = pcall(require, "hlslens")
        if not success then return end
        local overrideLens = function(render, posList, nearest, idx, relIdx)
          local _ = relIdx
          local lnum, col = unpack(posList[idx])
          local text, chunks
          if nearest then
            text = ("[%d/%d]"):format(idx, #posList)
            -- Use VM_Extend highlight group if available, otherwise fallback
            local vm_extend_hl = vim.fn.hlexists("VM_Extend") == 1 and "VM_Extend" or "HlSearchLensNear"
            chunks = { { " ", "Ignore" }, { text, vm_extend_hl } }
          else
            text = ("[%d]"):format(idx)
            chunks = { { " ", "Ignore" }, { text, "HlSearchLens" } }
          end
          render.setVirt(0, lnum - 1, col - 1, chunks, nearest)
        end
        local lensBak
        local config = require("hlslens.config")
        local gid = vim.api.nvim_create_augroup("VMlensIntegration", { clear = true })
        vim.api.nvim_create_autocmd("User", {
          pattern = { "visual_multi_start", "visual_multi_exit" },
          group = gid,
          callback = function(ev)
            if ev.match == "visual_multi_start" then
              lensBak = config.override_lens
              config.override_lens = overrideLens
            else
              config.override_lens = lensBak
            end
            -- Ensure hlslens redraws when VM starts/exits
            pcall(hlslens.start)
          end,
        })
      end
      vm_hlslens_integration()
    end,
  },

  -- Add avante.nvim for AI support
  {
    "yetone/avante.nvim",
    version = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-treesitter/nvim-treesitter",
      "stevearc/dressing.nvim",
      {
        'MeanderingProgrammer/render-markdown.nvim',
        opts = { file_types = { "markdown", "Avante" }, },
        ft = { "markdown", "Avante" },
      },
      -- Add img-clip.nvim for image pasting support
      {
        "HakonHarnes/img-clip.nvim",
        event = "VeryLazy",
        opts = {
          default = {
            embed_image_as_base64 = false,
            prompt_for_file_name = false,
            drag_and_drop = { insert_mode = true, },
            use_absolute_path = true, -- Recommended for macOS/Windows
          },
        },
      },
    },
    event = "VeryLazy",
    cmd = { "Avante", "AvanteAsk", "AvanteEdit", "AvanteToggle" },
    build = "make",
    opts = {
       provider = "gemini",
       gemini = {
         model = "gemini-2.5-pro-exp-03-25",
       },
    },
    config = function(_, opts)
      require("avante").setup(opts)

      -- Keymaps
      local map = vim.keymap.set
      local success, api = pcall(require, "avante.api")
      if not success then
        vim.notify("avante.api not found. Keymaps not set.", vim.log.levels.WARN)
        return
      end

      -- Cmd+L to toggle the sidebar/chat pane
      map("n", "<D-l>", function() api.toggle() end, { desc = "Avante: Toggle Sidebar" })

      -- Cmd+Shift+C to start editing selected code (buffer chat like)
      map({ "n", "v" }, "<D-S-c>", function() api.edit() end, { desc = "Avante: Edit Code" })
    end,
  },

  -- == Examples of Adding Plugins ==

  "andweeb/presence.nvim",
  {
    "ray-x/lsp_signature.nvim",
    event = "BufRead",
    config = function() require("lsp_signature").setup() end,
  },

  -- == Examples of Overriding Plugins ==

  -- Customize lualine options to show file path
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      -- Ensure opts and opts.sections are tables before proceeding
      opts = opts or {}
      opts.sections = opts.sections or {}
      -- Also ensure standard sections like lualine_c exist if needed later
      opts.sections.lualine_c = opts.sections.lualine_c or {}

      local function update_filename_path(sections, new_path)
          -- Now we can safely assume sections is a table
          for section_key, section_content in pairs(sections) do
             -- Ensure section_content is also a table before iterating with ipairs
             if type(section_content) == "table" then
                 for i, component in ipairs(section_content) do
                     local comp_name = type(component) == "table" and component[1] or component
                     if comp_name == "filename" then
                         if type(component) == "string" then
                             -- Replace string component with table format
                             section_content[i] = { "filename", path = new_path }
                         elseif type(component) == "table" then
                             -- Update existing table component
                             component[2] = component[2] or {}
                             component[2].path = new_path
                         end
                         return true -- Found and updated
                     end
                 end
             end
          end
          return false -- Not found
      end

      if not update_filename_path(opts.sections, 4) then
          table.insert(opts.sections.lualine_c, { "filename", path = 4 })
      end

      return opts -- Return the modified options
    end,
  },

  -- customize dashboard options
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        preset = {
          header = table.concat({
            " █████  ███████ ████████ ██████   ██████ ",
            "██   ██ ██         ██    ██   ██ ██    ██",
            "███████ ███████    ██    ██████  ██    ██",
            "██   ██      ██    ██    ██   ██ ██    ██",
            "██   ██ ███████    ██    ██   ██  ██████ ",
            "",
            "███    ██ ██    ██ ██ ███    ███",
            "████   ██ ██    ██ ██ ████  ████",
            "██ ██  ██ ██    ██ ██ ██ ████ ██",
            "██  ██ ██  ██  ██  ██ ██  ██  ██",
            "██   ████   ████   ██ ██      ██",
          }, "\n"),
        },
      },
    },
  },

  -- You can disable default plugins as follows:
  { "max397574/better-escape.nvim", enabled = false },

  -- You can also easily customize additional setup of plugins that is outside of the plugin's setup call
  {
    "L3MON4D3/LuaSnip",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.luasnip"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom luasnip configuration such as filetype extend or custom snippets
      local luasnip = require "luasnip"
      luasnip.filetype_extend("javascript", { "javascriptreact" })
    end,
  },

  {
    "windwp/nvim-autopairs",
    config = function(plugin, opts)
      require "astronvim.plugins.configs.nvim-autopairs"(plugin, opts) -- include the default astronvim config that calls the setup call
      -- add more custom autopairs configuration such as custom rules
      local npairs = require "nvim-autopairs"
      local Rule = require "nvim-autopairs.rule"
      local cond = require "nvim-autopairs.conds"
      npairs.add_rules(
        {
          Rule("$", "$", { "tex", "latex" })
            -- don't add a pair if the next character is %
            :with_pair(cond.not_after_regex "%%")
            -- don't add a pair if  the previous character is xxx
            :with_pair(
              cond.not_before_regex("xxx", 3)
            )
            -- don't move right when repeat character
            :with_move(cond.none())
            -- don't delete if the next character is xx
            :with_del(cond.not_after_regex "xx")
            -- disable adding a newline when you press <cr>
            :with_cr(cond.none()),
        },
        -- disable for .vim files, but it work for another filetypes
        Rule("a", "a", "-vim")
      )
    end,
  },

  {
    "AstroNvim/AstroNvim",
    opts = function(_, opts)
      -- 既存のオプションをキープ
      opts = opts or {}
      
      -- カラースキーマの設定を削除
      opts.colorscheme = nil
      
      return opts
    end,
  },

  -- Add mini.move for moving lines/selections
  {
    "echasnovski/mini.move",
    version = "*",
    event = "VeryLazy",
    config = function(_, opts)
      -- まず mini.move をデフォルト設定でセットアップ
      require('mini.move').setup(opts)

      -- Visual モード用のマッピングを明示的に設定
      -- <M-Down> で選択範囲を下へ移動
      vim.keymap.set('v', '<M-Down>', function() require('mini.move').move_selection('down') end, { desc = 'Move selection down' })
      -- <M-Up> で選択範囲を上へ移動
      vim.keymap.set('v', '<M-Up>', function() require('mini.move').move_selection('up') end, { desc = 'Move selection up' })

      -- Normal モードのマッピングも念のため設定
      -- <M-Down> で現在の行を下へ移動
      vim.keymap.set('n', '<M-Down>', function() require('mini.move').move_line('down') end, { desc = 'Move line down' })
      -- <M-Up> で現在の行を上へ移動
      vim.keymap.set('n', '<M-Up>', function() require('mini.move').move_line('up') end, { desc = 'Move line up' })
    end,
  },

  -- Customize indent-blankline settings (v3 syntax using config function)
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "ibl", -- Specify the main entry point for v3
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

  -- Override golangci_lint_ls configuration from astrocommunity
  {
    "AstroNvim/astrolsp",
    opts = function(_, opts)
      if not opts.config then opts.config = {} end
      opts.config.golangci_lint_ls = {
        init_options = {
          command = {
            "sh", "-c", "cd application/new && golangci-lint run --out-format json --show-stats=false --issues-exit-code=1"
          },
        },
      }
      return opts
    end,
  },
}
