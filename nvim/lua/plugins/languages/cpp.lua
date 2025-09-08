return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts = opts or {}
      local ensure = opts.ensure_installed or {}
      local add = { "c", "cpp", "cmake", "make" }
      for _, lang in ipairs(add) do
        if not vim.tbl_contains(ensure, lang) then
          table.insert(ensure, lang)
        end
      end
      opts.ensure_installed = ensure
      return opts
    end,
  },

  -- Keymaps: integrate lsp-actions for C/C++
  {
    "neovim/nvim-lspconfig",
    ft = { "c", "cpp", "objc", "objcpp" },
    config = function()
      local ok, lsp_actions = pcall(require, "utils.lsp-actions")
      if not ok then return end
      local opts = { buffer = true, silent = true }
      vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
      vim.keymap.set("n", "<D-S-r>", lsp_actions.cpp_refactor_menu or lsp_actions.language_specific_code_action, opts)
      vim.keymap.set("n", "<M-S-r>", lsp_actions.cpp_refactor_menu or lsp_actions.language_specific_code_action, opts)
    end,
  },

  {
    "mfussenegger/nvim-dap",
    ft = { "c", "cpp", "objc", "objcpp" },
    dependencies = { "nvim-neotest/nvim-nio" },
    config = function()
      local ok, dap = pcall(require, "dap")
      if not ok then return end

      local mason = vim.fn.stdpath("data") .. "/mason"
      local adapter = mason .. "/bin/codelldb"
      if vim.fn.executable(adapter) ~= 1 then return end

      dap.adapters.codelldb = {
        type = "server",
        port = "${port}",
        executable = { command = adapter, args = { "--port", "${port}" } },
      }

      local cfg = {
        {
          name = "Launch (codelldb)",
          type = "codelldb",
          request = "launch",
          program = function()
            return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
          end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
      }
      dap.configurations.cpp = cfg
      dap.configurations.c = cfg
      dap.configurations.objc = cfg
      dap.configurations.objcpp = cfg
    end,
  },

  {
    "p00f/clangd_extensions.nvim",
    ft = { "c", "cpp", "objc", "objcpp" },
    dependencies = { "neovim/nvim-lspconfig" },
    config = function()
      local ok_lsp, lspconfig = pcall(require, "lspconfig")
      if not ok_lsp then return end

      local util = lspconfig.util
      local root = util.root_pattern("compile_commands.json", "compile_flags.txt", ".git")

      lspconfig.clangd.setup({
        cmd = { "clangd", "--background-index", "--clang-tidy" },
        root_dir = function(fname)
          return root(fname) or util.find_git_ancestor(fname)
        end,
        init_options = { clangdFileStatus = true },
      })

      pcall(function()
        require("clangd_extensions").setup({})
      end)

      local ok_null, null_ls = pcall(require, "null-ls")
      if ok_null then
        null_ls.register({
          null_ls.builtins.formatting.clang_format.with({
            filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
          }),
        })
      end
    end,
  },
}
