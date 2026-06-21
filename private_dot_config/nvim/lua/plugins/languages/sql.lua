return {
  -- Register sqruff linter + formatter via none-ls (once)
  {
    name = "sql-tools-setup",
    dir = vim.fn.stdpath("config"),
    ft = { "sql", "mysql", "plsql" },
    dependencies = { "nvimtools/none-ls.nvim" },
    config = function()
      local null_ls_ok, null_ls = pcall(require, "null-ls")
      if null_ls_ok and not vim.g._sql_null_ls_registered then
        vim.g._sql_null_ls_registered = true

        local h = require("null-ls.helpers")
        local methods = require("null-ls.methods")

        local global_config = vim.fn.expand("~/.sqlfluff")
        local function sqruff_args(subcmd_args)
          local args = {}
          vim.list_extend(args, subcmd_args)
          if vim.fn.filereadable(global_config) == 1 then
            vim.list_extend(args, { "--config", global_config })
          end
          table.insert(args, "-")
          return args
        end

        null_ls.register(h.make_builtin({
          name = "sqruff_lint",
          method = methods.internal.DIAGNOSTICS,
          filetypes = { "sql", "mysql", "plsql" },
          generator_opts = {
            command = "sqruff",
            args = sqruff_args({ "lint", "--format", "json" }),
            to_stdin = true,
            format = "raw",
            check_exit_code = { 0, 1 },
            on_output = function(params, done)
              local diagnostics = {}
              if not params.output then
                return done(diagnostics)
              end
              local ok, decoded = pcall(vim.json.decode, params.output)
              if not ok or not decoded then
                return done(diagnostics)
              end
              -- Output format: { "<string>": [ { range, message, severity, code } ] }
              local items = decoded["<string>"] or {}
              for _, v in ipairs(items) do
                local sev = v.severity == "Error" and 1 or 2
                table.insert(diagnostics, {
                  row = v.range.start.line,
                  col = v.range.start.character,
                  end_row = v.range["end"].line,
                  end_col = v.range["end"].character,
                  source = "sqruff",
                  message = v.message,
                  code = v.code,
                  severity = sev,
                })
              end
              return done(diagnostics)
            end,
          },
          factory = h.generator_factory,
        }))

        null_ls.register(h.make_builtin({
          name = "sqruff_fix",
          method = methods.internal.FORMATTING,
          filetypes = { "sql", "mysql", "plsql" },
          generator_opts = {
            command = "sqruff",
            args = sqruff_args({ "fix" }),
            to_stdin = true,
          },
          factory = h.generator_factory,
        }))
      end
    end,
  },
}
