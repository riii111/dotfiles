return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts = opts or {}
      local ensure = opts.ensure_installed or {}
      local add = { "terraform", "hcl" }
      for _, lang in ipairs(add) do
        if not vim.tbl_contains(ensure, lang) then
          table.insert(ensure, lang)
        end
      end
      opts.ensure_installed = ensure
      return opts
    end,
  },

  {
    "neovim/nvim-lspconfig",
    ft = { "terraform", "hcl", "terraform-vars" },
    dependencies = { "nvimtools/none-ls.nvim" },
    config = function()
      -- Configure terraform-ls
      vim.lsp.config('terraform_ls', {
        cmd = { "terraform-ls", "serve" },
        root_markers = { ".terraform", ".git" },
        filetypes = { "terraform", "hcl", "terraform-vars" },
      })

      vim.lsp.enable('terraform_ls')

      -- Setup null-ls for formatting and linting
      local ok_null, null_ls = pcall(require, "null-ls")
      if not ok_null then return end

      -- Terraform fmt formatter
      local terraform_fmt = {
        method = null_ls.methods.FORMATTING,
        filetypes = { "terraform", "hcl", "terraform-vars" },
        generator = null_ls.generator({
          command = "terraform",
          args = { "fmt", "-" },
          to_stdin = true,
          from_stdout = true,
        }),
      }

      -- tflint diagnostics
      local tflint_diagnostics = {
        method = null_ls.methods.DIAGNOSTICS,
        filetypes = { "terraform", "hcl" },
        generator = null_ls.generator({
          command = "tflint",
          args = { "--format", "json" },
          to_stdin = false,
          from_stderr = false,
          format = "json",
          check_exit_code = function(code)
            return code <= 1
          end,
          on_output = function(params)
            local diagnostics = {}
            if params.output and params.output.issues then
              for _, issue in ipairs(params.output.issues) do
                if issue.range then
                  table.insert(diagnostics, {
                    row = issue.range.start.line,
                    col = issue.range.start.column - 1,
                    end_row = issue.range["end"].line,
                    end_col = issue.range["end"].column - 1,
                    source = "tflint",
                    message = issue.message,
                    code = issue.rule.name,
                    severity = issue.rule.severity == "error" and 1 or 2,
                  })
                end
              end
            end
            return diagnostics
          end,
        }),
      }

      null_ls.register(terraform_fmt)
      null_ls.register(tflint_diagnostics)

      -- Keymaps: integrate lsp-actions for Terraform
      local lsp_actions = require("utils.lsp-actions")

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "terraform", "hcl", "terraform-vars" },
        callback = function()
          local opts = { buffer = true, silent = true }

          vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
          vim.keymap.set("n", "<D-S-r>", lsp_actions.terraform_refactor_menu, opts)
          vim.keymap.set("n", "<M-S-r>", lsp_actions.terraform_refactor_menu, opts)
        end,
      })
    end,
  },
}
