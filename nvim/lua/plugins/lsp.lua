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
      vim.env.GOPATH = vim.env.GOPATH or vim.fn.expand("$HOME/go")

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

        -- Configure LSP behavior (diagnostics, etc.) but let lspsaga.nvim handle keymaps
        -- All keymaps are handled by lspsaga.nvim on LspAttach
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
        cmd = { vim.fn.expand("$HOME/go/bin/gopls") },  -- 明示的なパス
        filetypes = { 'go', 'gomod', 'gowork', 'gotmpl' },
        root_dir = function(fname)
          return lspconfig.util.root_pattern("go.mod", "go.work")(fname)
              or lspconfig.util.find_git_ancestor(fname)
        end,
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

      -- Setup TypeScript Language Server
      lspconfig.ts_ls.setup({
        on_attach = on_attach,
        capabilities = capabilities,
        filetypes = { "typescript", "typescriptreact", "typescript.tsx", "javascript", "javascriptreact" },
        root_dir = lspconfig.util.root_pattern("package.json", "tsconfig.json", "jsconfig.json", ".git"),
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
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "n", false)
            return true
          end,
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
