return {
  -- LSP Configuration
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    cond = not vim.g.vscode,
    dependencies = {
      "williamboman/mason.nvim",
    },
    priority = 50,
    config = function()
      -- Ensure Go environment variables are set for gopls
      vim.env.GOROOT = vim.env.GOROOT or vim.fn.system("go env GOROOT"):gsub("\n", "")
      vim.env.GOPATH = vim.env.GOPATH or vim.fn.system("go env GOPATH"):gsub("\n", "")

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

        -- Configure LSP behavior (diagnostics, etc.) but let lspsaga.nvim handle keymaps
        -- All keymaps are handled by lspsaga.nvim on LspAttach

        if client.name == "kotlin_lsp" then
          local ok_actions, lsp_actions = pcall(require, "utils.lsp-actions")
          if ok_actions then
            vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
            vim.keymap.set("n", "<D-S-r>", lsp_actions.kotlin_refactor_menu, opts)
            vim.keymap.set("n", "<M-S-r>", lsp_actions.kotlin_refactor_menu, opts)
          end
        end
      end

      local capabilities = vim.lsp.protocol.make_client_capabilities()

      -- Setup LSP servers directly
      vim.lsp.config('lua_ls', {
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

      vim.lsp.enable('lua_ls')

      -- Setup gopls
      vim.lsp.config('gopls', {
        on_attach = on_attach,
        capabilities = capabilities,
        cmd = { "gopls" },  -- PATH経由で検索
        filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
        root_markers = { "go.mod", "go.work", ".git" },
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

      vim.lsp.enable('gopls')

      -- Setup TypeScript Language Server
      vim.lsp.config('ts_ls', {
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "typescript", "typescriptreact", "typescript.tsx", "javascript", "javascriptreact" },
        root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
        settings = {
          typescript = {
            inlayHints = {
              includeInlayParameterNameHints = 'none',
              includeInlayParameterNameHintsWhenArgumentMatchesName = false,
              includeInlayFunctionParameterTypeHints = false,
              includeInlayVariableTypeHints = false,
              includeInlayVariableTypeHintsWhenTypeMatchesName = false,
              includeInlayPropertyDeclarationTypeHints = false,
              includeInlayFunctionLikeReturnTypeHints = false,
              includeInlayEnumMemberValueHints = false,
            },
            suggest = {
              includeCompletionsForModuleExports = true,
            },
            format = {
              enable = false,  -- Biomeでフォーマットするため無効化
            },
          },
          javascript = {
            inlayHints = {
              includeInlayParameterNameHints = 'none',
              includeInlayParameterNameHintsWhenArgumentMatchesName = false,
              includeInlayFunctionParameterTypeHints = false,
              includeInlayVariableTypeHints = false,
              includeInlayVariableTypeHintsWhenTypeMatchesName = false,
              includeInlayPropertyDeclarationTypeHints = false,
              includeInlayFunctionLikeReturnTypeHints = false,
              includeInlayEnumMemberValueHints = false,
            },
            suggest = {
              includeCompletionsForModuleExports = true,
            },
            format = {
              enable = false,  -- Biomeでフォーマットするため無効化
            },
          },
        },
      })

      vim.lsp.enable('ts_ls')

      -- Kotlin LSP (JetBrains kotlin-lsp)
      do
        local util = require("lspconfig.util")
        local jdk21 = vim.fn.systemlist("/usr/libexec/java_home -v 21")[1]
        local java_home = (jdk21 and #jdk21 > 0) and jdk21 or vim.env.JAVA_HOME
        local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/kotlin-lsp"
        local kotlin_cmd = vim.fn.executable(mason_bin) == 1 and { mason_bin, "--stdio" } or { "kotlin-lsp", "--stdio" }

        vim.lsp.config("kotlin_lsp", {
          cmd = kotlin_cmd,
          cmd_env = {
            JAVA_HOME = java_home,
            JDK_HOME = java_home,
            PATH = (java_home and (java_home .. "/bin:" .. vim.env.PATH)) or vim.env.PATH,
          },
          filetypes = { "kotlin" },
          root_markers = { "settings.gradle.kts", "settings.gradle", "build.gradle.kts", "build.gradle", ".git" },
          on_attach = on_attach,
          capabilities = capabilities,
        })

        -- Ensure enable on filetype to avoid missed autostart
        vim.api.nvim_create_autocmd("FileType", {
          pattern = "kotlin",
          callback = function()
            vim.lsp.enable("kotlin_lsp")
          end,
        })
      end

      -- Setup basedpyright for Python using Neovim 0.11 API
      local function find_basedpyright_cmd()
        local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"
        local candidates = {
          "basedpyright-langserver",
          "basedpyright",
          "pyright-langserver",
        }
        for _, exe in ipairs(candidates) do
          local mason_path = mason_bin .. exe
          if vim.fn.executable(mason_path) == 1 then
            return mason_path
          end
          if vim.fn.executable(exe) == 1 then
            return exe
          end
        end
        return "basedpyright-langserver"
      end

      vim.lsp.config("basedpyright", {
        name = "basedpyright",
        cmd = { find_basedpyright_cmd(), "--stdio" },
        filetypes = { "python" },
        on_attach = on_attach,
        capabilities = capabilities,
        settings = {
          basedpyright = {
            disableOrganizeImports = true,
          },
        },
      })

      vim.lsp.enable("basedpyright")

      -- Safety net: ensure client starts on FileType event in case autostart fails
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function(args)
          local bufnr = args.buf
          local attached = false
          for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
            if client.name == "basedpyright" then
              attached = true
              break
            end
          end
          if not attached then
            vim.lsp.enable("basedpyright")
          end
        end,
      })

    end,
  },

  -- Completion
  {
    "saghen/blink.cmp",
    lazy = false,
    cond = not vim.g.vscode,
    dependencies = "rafamadriz/friendly-snippets",
    version = "v0.*",
    opts = {
      keymap = {
        preset = "default",
        ["<CR>"] = {
          function(cmp)
            if cmp.is_visible() then
              return cmp.accept()
            end
            local has_autopairs, autopairs = pcall(require, "nvim-autopairs")
            if has_autopairs then
              local default_cr = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
              local autopairs_cr = autopairs.autopairs_cr()
              if autopairs_cr ~= default_cr then
                vim.api.nvim_feedkeys(autopairs_cr, "n", true)
                return true
              end
            end
            return false
          end,
          "fallback",
        },
      },
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
    cond = not vim.g.vscode,
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local null_ls = require("null-ls")
      null_ls.setup({
        sources = {
          null_ls.builtins.formatting.stylua,
          null_ls.builtins.diagnostics.golangci_lint.with({
            cwd = function(params)
              local found = vim.fs.find("go.mod", { upward = true, path = params.bufname })
              return found[1] and vim.fs.dirname(found[1]) or nil
            end,
            extra_args = function(params)
              local golangci_file = vim.fs.find(".golangci.yml", { upward = true, path = params.bufname })
              local root = golangci_file[1] and vim.fs.dirname(golangci_file[1])
                or vim.fs.find(".git", { upward = true, path = params.bufname, type = "directory" })[1] and vim.fs.dirname(vim.fs.find(".git", { upward = true, path = params.bufname, type = "directory" })[1])

              local args = { "--out-format", "json" }
              if root and golangci_file[1] then
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


  -- DAP (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    cond = not vim.g.vscode,
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
    cond = not vim.g.vscode,
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
