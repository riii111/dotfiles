return {
  {
    "neovim/nvim-lspconfig",
    ft = "python",
    config = function()
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

      vim.lsp.config('basedpyright', {
        cmd = { find_basedpyright_cmd(), "--stdio" },
        root_markers = { "pyproject.toml", "setup.py", "requirements.txt", "Pipfile", ".git" },
        settings = {
          basedpyright = {
            disableOrganizeImports = true,
          },
        },
      })

      vim.lsp.enable('basedpyright')
    end,
  },
  {
    "mfussenegger/nvim-dap-python",
    dependencies = {
      "mfussenegger/nvim-dap",
    },
    config = function()
      local function get_python_path()
        local cwd = vim.fn.getcwd()
        if vim.fn.executable(cwd .. "/.venv/bin/python") == 1 then
          return cwd .. "/.venv/bin/python"
        elseif vim.fn.executable(cwd .. "/venv/bin/python") == 1 then
          return cwd .. "/venv/bin/python"
        else
          return "python3"
        end
      end
      
      require("dap-python").setup(get_python_path())
      
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function()
          local opts = { buffer = true, silent = true }
          vim.keymap.set("n", "<F5>", function()
            require("dap-python").test_method()
          end, vim.tbl_extend("force", opts, { desc = "Debug Python test method" }))

          vim.keymap.set("n", "<leader>dt", function()
            require("dap-python").test_method()
          end, vim.tbl_extend("force", opts, { desc = "Debug Python test method" }))

          vim.keymap.set("n", "<leader>dc", function()
            require("dap-python").test_class()
          end, vim.tbl_extend("force", opts, { desc = "Debug Python test class" }))
        end,
      })
    end,
    ft = "python",
  },

  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    ft = "python",
    config = function()
      local null_ls = require("null-ls")
      
      -- Detect project-specific ruff command to respect project configuration
      local function get_ruff_command()
        -- Start from current file's directory and search upward
        local current_file = vim.fn.expand("%:p")
        local current_dir = vim.fn.fnamemodify(current_file, ":h")
        
        -- Search upward for Python project files
        local project_root = vim.fs.find({"pyproject.toml", "setup.py", "requirements.txt", "Pipfile"}, {
          upward = true,
          path = current_dir,
        })[1]
        
        if project_root then
          local project_dir = vim.fn.fnamemodify(project_root, ":h")
          if vim.fn.filereadable(project_dir .. "/pyproject.toml") == 1 then
            if vim.fn.executable("uv") == 1 then
              return "uv"
            elseif vim.fn.filereadable(project_dir .. "/poetry.lock") == 1 then
              return "poetry"
            elseif vim.fn.executable(project_dir .. "/.venv/bin/ruff") == 1 then
              return project_dir .. "/.venv/bin/ruff"
            elseif vim.fn.executable(project_dir .. "/venv/bin/ruff") == 1 then
              return project_dir .. "/venv/bin/ruff"
            else
              return "python"
            end
          elseif vim.fn.filereadable(project_dir .. "/ruff.toml") == 1 then
            return "ruff"
          end
        end
       
        return "ruff"
      end
      
      local function get_ruff_args(action)
        local cmd = get_ruff_command()
        local base_args = {}
        
        if cmd == "uv" then
          base_args = { "run", "ruff" }
        elseif cmd == "poetry" then
          base_args = { "run", "ruff" }
        elseif cmd == "python" then
          base_args = { "-m", "ruff" }
        end
        
        if action == "format" then
          return vim.list_extend(base_args, { "format", "--stdin-filename", "$FILENAME", "-" })
        elseif action == "check" then
          return vim.list_extend(base_args, { "check", "--output-format", "json", "$FILENAME" })
        end
        
        return base_args
      end
      
      local ruff_diagnostics = {
        method = null_ls.methods.DIAGNOSTICS,
        filetypes = { "python" },
        generator = null_ls.generator({
          command = get_ruff_command(),
          args = get_ruff_args("check"),
          to_stdin = false,
          from_stderr = true,
          format = "json",
          check_exit_code = function(code)
            return code <= 1
          end,
          on_output = function(params)
            local diagnostics = {}
            if params.output then
              for _, diag in ipairs(params.output) do
                if diag.location then
                  table.insert(diagnostics, {
                    row = diag.location.row,
                    col = diag.location.column - 1,
                    end_row = diag.end_location and diag.end_location.row or diag.location.row,
                    end_col = diag.end_location and diag.end_location.column - 1 or diag.location.column,
                    source = "ruff",
                    message = diag.message,
                    code = diag.code,
                    severity = diag.severity == "error" and 1 or 2,
                  })
                end
              end
            end
            return diagnostics
          end,
        }),
      }
      
      local ruff_formatting = {
        method = null_ls.methods.FORMATTING,
        filetypes = { "python" },
        generator = null_ls.generator({
          command = get_ruff_command(),
          args = get_ruff_args("format"),
          to_stdin = true,
          from_stdout = true,
        }),
      }
      
      null_ls.register(ruff_formatting)
      null_ls.register(ruff_diagnostics)
      
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.py",
        callback = function()
          vim.lsp.buf.format({
            filter = function(client)
              return client.name == "null-ls"
            end,
            timeout_ms = 5000,
          })
        end,
      })
    end,
  },
}
