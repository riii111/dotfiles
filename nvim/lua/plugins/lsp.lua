return {
  -- LSP Configuration
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
    },
    config = function()
      local lspconfig = require("lspconfig")

      -- LSP settings
---@diagnostic disable-next-line: unused-local
      local on_attach = function(client, bufnr)
        local opts = { buffer = bufnr, silent = true }
        vim.diagnostic.config({
          virtual_text = true,
          signs = true,
          underline = true,
          update_in_insert = false,
          severity_sort = true,
        })

        -- Key mappings
        vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
        vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, opts)
        vim.keymap.set("n", "<space>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set("n", "<space>ca", vim.lsp.buf.code_action, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "<space>f", function()
          vim.lsp.buf.format { async = true }
        end, opts)
      end

      local capabilities = vim.lsp.protocol.make_client_capabilities()

      -- Setup LSP servers directly
      lspconfig.lua_ls.setup({
        on_attach = on_attach,
        capabilities = capabilities,
        settings = {
          Lua = {
            runtime = {
              version = "LuaJIT",
            },
            diagnostics = {
              globals = { "vim" },
            },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
            },
            telemetry = {
              enable = false,
            },
          },
        },
      })

      -- Setup gopls
      lspconfig.gopls.setup({
        on_attach = on_attach,
        capabilities = capabilities,
        cmd = { 'gopls' },
        filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
        root_dir = lspconfig.util.root_pattern('.golangci.yml', 'go.work', '.git'),
        settings = {
          gopls = {
            hints = {
              assignVariableTypes = false,
              compositeLiteralFields = false,
              compositeLiteralTypes = false,
              constantValues = false,
              functionTypeParameters = false,
              parameterNames = false,
              rangeVariableTypes = false,
            },
            analyses = {
              unusedparams = false,
              shadow = false,
            },
            staticcheck = false, -- Disable gopls built-in diagnostics to use golangci-lint via null-ls
            buildFlags = { "-tags=unit,e2e" },
          },
        },
      })

    end,
  },

  -- Completion
  {
    "saghen/blink.cmp",
    lazy = false,
    dependencies = "rafamadriz/friendly-snippets",
    version = "v0.*",
    opts = {
      keymap = { preset = "default" },
      appearance = {
        use_nvim_cmp_as_default = true,
        nerd_font_variant = "mono"
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
    },
    opts_extend = { "sources.default" }
  },

  -- Formatting and linting
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local null_ls = require("null-ls")
      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.stylua,
          null_ls.builtins.diagnostics.golangci_lint.with({
            cwd = function(params)
              return require("lspconfig.util").root_pattern("go.mod")(params.bufname)
            end,
            extra_args = function(params)
              local root = require("lspconfig.util").root_pattern(".golangci.yml", ".git")(params.bufname)
              local args = { "--out-format", "json" }
              if root then
                table.insert(args, "--config")
                table.insert(args, root .. "/.golangci.yml")
              end
              return args
            end,
            condition = function(utils)
              return utils.root_has_file("go.mod") and utils.has_file(".golangci.yml")
            end,
          }),
        },
      })
    end,
  },

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
      
      -- Definition Preview
      vim.keymap.set("n", "gp", "<cmd>Lspsaga peek_definition<CR>", vim.tbl_extend("force", opts, { desc = "Peek Definition" }))
      vim.keymap.set("n", "gt", "<cmd>Lspsaga peek_type_definition<CR>", vim.tbl_extend("force", opts, { desc = "Peek Type Definition" }))
      
      -- Enhanced Hover (K キーを置き換え)
      vim.keymap.set("n", "K", "<cmd>Lspsaga hover_doc<CR>", vim.tbl_extend("force", opts, { desc = "Hover Documentation" }))
      
      -- Enhanced Diagnostics Navigation
      vim.keymap.set("n", "[d", "<cmd>Lspsaga diagnostic_jump_prev<CR>", vim.tbl_extend("force", opts, { desc = "Previous Diagnostic" }))
      vim.keymap.set("n", "]d", "<cmd>Lspsaga diagnostic_jump_next<CR>", vim.tbl_extend("force", opts, { desc = "Next Diagnostic" }))
      vim.keymap.set("n", "<leader>d", "<cmd>Lspsaga show_line_diagnostics<CR>", vim.tbl_extend("force", opts, { desc = "Show Line Diagnostics" }))
      vim.keymap.set("n", "<leader>D", "<cmd>Lspsaga show_cursor_diagnostics<CR>", vim.tbl_extend("force", opts, { desc = "Show Cursor Diagnostics" }))
      
      -- Call Hierarchy
      vim.keymap.set("n", "<leader>ci", "<cmd>Lspsaga incoming_calls<CR>", vim.tbl_extend("force", opts, { desc = "Incoming Calls" }))
      vim.keymap.set("n", "<leader>co", "<cmd>Lspsaga outgoing_calls<CR>", vim.tbl_extend("force", opts, { desc = "Outgoing Calls" }))
      
      -- Enhanced Rename (補完として追加、既存のlsp-actions.luaと共存)
      vim.keymap.set("n", "<leader>rn", "<cmd>Lspsaga rename<CR>", vim.tbl_extend("force", opts, { desc = "LSP Saga Rename" }))
    end,
    event = "LspAttach",
  },

  -- DAP (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "nvim-neotest/nvim-nio",
    },
    config = function()
      local dap = require("dap")
      local dapui = require("dapui")

      dapui.setup()

      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end
    end,
  },

  -- Symbol usage display (IntelliJ IDEA-like)
  {
    "Wansmer/symbol-usage.nvim",
    event = "LspAttach",
    config = function()
      require("symbol-usage").setup({
        kinds = {
          vim.lsp.protocol.SymbolKind.Function,
          vim.lsp.protocol.SymbolKind.Method,
          vim.lsp.protocol.SymbolKind.Variable,
          vim.lsp.protocol.SymbolKind.Class,
          vim.lsp.protocol.SymbolKind.Interface,
          vim.lsp.protocol.SymbolKind.Module,
          vim.lsp.protocol.SymbolKind.Property,
          vim.lsp.protocol.SymbolKind.Struct,
          vim.lsp.protocol.SymbolKind.Constant,
          vim.lsp.protocol.SymbolKind.Constructor,
          vim.lsp.protocol.SymbolKind.Enum,
          vim.lsp.protocol.SymbolKind.EnumMember,
          vim.lsp.protocol.SymbolKind.TypeParameter,
        },
        text_format = function(symbol)
          local res = {}
          local round_start = {"", ""}
          local round_end = {"", ""}

          if symbol.references then
            local usage = symbol.references <= 1 and "usage" or "usages"
            local num = symbol.references == 0 and "no" or symbol.references
            table.insert(res, round_start[1] .. num .. " " .. usage .. round_end[1])
          end

          return table.concat(res, " ")
        end,
        vt_position = "end_of_line",
      })
    end,
  },


}
