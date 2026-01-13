return {
  {
    "ray-x/go.nvim",
    dependencies = {
      "ray-x/guihua.lua",
      "neovim/nvim-lspconfig",
      "nvim-treesitter/nvim-treesitter",
    },
    config = function()
      require("go").setup({
        goimports = "goimports",
        fillstruct = "gopls",
        dap_debug = false,
        textobjects = true,
        lsp_cfg = true,
        lsp_inlay_hints = {
          enable = false,
        },
      })

      local lsp_actions = require("utils.lsp-actions")

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "go",
        callback = function()
          local opts = { buffer = true, silent = true }

          vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
          vim.keymap.set("n", "<D-S-r>", lsp_actions.go_refactor_menu, opts)
          vim.keymap.set("n", "<M-S-r>", lsp_actions.go_refactor_menu, opts)
        end,
      })
    end,
    ft = { "go", "gomod" },
    build = ':lua require("go.install").update_all_sync()'
  },

  -- Go DAP integration
  {
    "leoluz/nvim-dap-go",
    dependencies = {
      "mfussenegger/nvim-dap",
    },
    config = function()
      require("dap-go").setup({
        dap_configurations = {
          {
            type = "go",
            name = "Attach remote",
            mode = "remote",
            request = "attach",
          },
        },
        delve = {
          path = "dlv",
          initialize_timeout_sec = 20,
          port = "${port}",
          args = {},
          build_flags = "",
        },
      })

      -- Key mappings for Go debugging
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "go",
        callback = function()
          local opts = { buffer = true, silent = true }
          vim.keymap.set("n", "<F5>", function()
            require("dap-go").debug_test()
          end, vim.tbl_extend("force", opts, { desc = "Debug Go test" }))

          vim.keymap.set("n", "<leader>dt", function()
            require("dap-go").debug_test()
          end, vim.tbl_extend("force", opts, { desc = "Debug Go test" }))

          vim.keymap.set("n", "<leader>dl", function()
            require("dap-go").debug_last_test()
          end, vim.tbl_extend("force", opts, { desc = "Debug last Go test" }))
        end,
      })
    end,
    ft = "go",
  },
}
