return {
  -- LSP Configuration (base plugin, actual server configs in language modules)
  {
    "neovim/nvim-lspconfig",
    lazy = false,
    cond = not vim.g.vscode,
    dependencies = {
      "williamboman/mason.nvim",
    },
    priority = 50,
    config = function()
      vim.env.GOROOT = vim.env.GOROOT or vim.fn.system("go env GOROOT"):gsub("\n", "")
      vim.env.GOPATH = vim.env.GOPATH or vim.fn.system("go env GOPATH"):gsub("\n", "")

      vim.diagnostic.config({
        virtual_text = true,
        signs = true,
        underline = true,
        update_in_insert = false,
        severity_sort = true,
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
          -- Kotlin ktlint
          null_ls.builtins.formatting.ktlint.with({
            filetypes = { "kotlin" },
          }),
          null_ls.builtins.diagnostics.ktlint.with({
            filetypes = { "kotlin" },
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
