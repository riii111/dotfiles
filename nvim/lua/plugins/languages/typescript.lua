return {
  {
    "neovim/nvim-lspconfig",
    ft = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
    config = function()
      vim.lsp.config('ts_ls', {
        cmd = { vim.fn.stdpath("data") .. "/mason/bin/typescript-language-server", "--stdio" },
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
              enable = false,
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
              enable = false,
            },
          },
        },
      })

      vim.lsp.enable('ts_ls')

      -- Register biome sources (once, if project uses biome)
      local null_ls_ok, null_ls = pcall(require, "null-ls")
      if null_ls_ok and not vim.g._typescript_null_ls_registered then
        local has_biome = vim.fn.filereadable(vim.fn.getcwd() .. "/biome.json") == 1
          and vim.fn.filereadable(vim.fn.getcwd() .. "/package.json") == 1

        if has_biome then
          vim.g._typescript_null_ls_registered = true
          local h = require("null-ls.helpers")

          local biome_diagnostics = h.make_builtin({
            name = "biome",
            method = null_ls.methods.DIAGNOSTICS,
            filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
            generator_opts = {
              command = "npm",
              args = { "run", "lint:check", "--", "$FILENAME" },
              to_stdin = false,
              from_stderr = false,
              format = "json",
              check_exit_code = function(code)
                return code <= 1
              end,
              on_output = h.diagnostics.from_json({
                attributes = {
                  row = "location.line",
                  col = "location.column",
                  source = "biome",
                  message = "message",
                  severity = function(diag)
                    return diag.severity == "error" and 1 or 2
                  end,
                },
              }),
            },
            factory = h.generator_factory,
          })

          local biome_formatting = h.make_builtin({
            name = "biome",
            method = null_ls.methods.FORMATTING,
            filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
            generator_opts = {
              command = "npm",
              args = { "run", "lint:fix", "--", "$FILENAME" },
              to_stdin = false,
            },
            factory = h.generator_factory,
          })

          null_ls.register(biome_formatting)
          null_ls.register(biome_diagnostics)
        end
      end
    end,
  },
}
