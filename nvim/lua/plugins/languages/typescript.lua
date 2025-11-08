return {
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
    config = function()
      local null_ls = require("null-ls")
      
      -- Biome向けのカスタムソース（yarn経由）
      local biome_diagnostics = {
        method = null_ls.methods.DIAGNOSTICS,
        filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
        generator = null_ls.generator({
          command = "yarn",
          args = { "biome", "check", "--reporter=json", "$FILENAME" },
          to_stdin = false,
          from_stderr = false,
          format = "json",
          check_exit_code = function(code)
            -- Biomeはエラーがある場合でも0を返すことがある
            return code <= 1
          end,
          on_output = function(params)
            local diagnostics = {}
            if params.output and params.output.diagnostics then
              for _, diag in ipairs(params.output.diagnostics) do
                table.insert(diagnostics, {
                  row = diag.location.line,
                  col = diag.location.column - 1,
                  end_row = diag.location.line,
                  end_col = diag.location.column,
                  source = "biome",
                  message = diag.message,
                  severity = diag.severity == "error" and 1 or 2,
                })
              end
            end
            return diagnostics
          end,
        }),
      }
      
      -- Biome向けのフォーマッター（yarn lint:fix）
      local biome_formatting = {
        method = null_ls.methods.FORMATTING,
        filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
        generator = null_ls.generator({
          command = "yarn",
          args = { "lint:fix", "$FILENAME" },
          to_stdin = false,
        }),
      }
      
      null_ls.register(biome_formatting)
      null_ls.register(biome_diagnostics)
      
      -- 保存時の自動フォーマット設定
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = { "*.js", "*.jsx", "*.ts", "*.tsx", "*.json", "*.jsonc" },
        callback = function()
          vim.lsp.buf.format({
            filter = function(client)
              -- TypeScript LSPのフォーマットは無効化しているので、null-lsのみ使用
              return client.name == "null-ls"
            end,
            timeout_ms = 5000,
          })
        end,
      })

      -- キーマップ設定
      local lsp_actions = require("utils.lsp-actions")

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
        callback = function()
          local opts = { buffer = true, silent = true }

          vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
          vim.keymap.set("n", "<D-S-r>", lsp_actions.typescript_refactor_menu, opts)
          vim.keymap.set("n", "<M-S-r>", lsp_actions.typescript_refactor_menu, opts)
        end,
      })
    end,
  },
}
