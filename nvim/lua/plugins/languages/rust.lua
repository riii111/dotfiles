return {
  {
    "mrcjkb/rustaceanvim",
    version = "^5",
    lazy = false,
    init = function()
      -- Configure rustaceanvim before loading
      vim.g.rustaceanvim = {
        server = {
          load_vscode_settings = false,
          default_settings = {
            ["rust-analyzer"] = {
              checkOnSave = {
                command = "clippy",  -- ファイル保存時にclippyを自動実行
                -- 重かったら以下に変更
                -- command = "check",
                -- allTargets = false, -- ビルドターゲットを制限するだけ
              },
              cargo = {
                extraEnv = {
                  CARGO_TARGET_DIR = ".nvim/target",
                },
              },
              procMacro = {
                enable = true,
              },
              diagnostics = {
                enable = true,
                enableExperimental = true,
              },
              inlayHints = {
                bindingModeHints = { enable = false },
                chainingHints = { enable = false },
                closingBraceHints = { enable = false, minLines = 25 },
                closureReturnTypeHints = { enable = "never" },
                lifetimeElisionHints = { enable = "never", useParameterNames = false },
                maxLength = 25,
                parameterHints = { enable = false },
                reborrowHints = { enable = "never" },
                renderColons = true,
                typeHints = { enable = false, hideClosureInitialization = false, hideNamedConstructor = false },
              },
            },
          },
        },
      }
    end,
    config = function()
      local lsp_actions = require("utils.lsp-actions")

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "rust",
        callback = function()
          local opts = { buffer = true, silent = true }

          vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
          vim.keymap.set("n", "<D-S-r>", lsp_actions.rust_refactor_menu, opts)
          vim.keymap.set("n", "<M-S-r>", lsp_actions.rust_refactor_menu, opts)
          vim.keymap.set("n", "<leader>rr", function()
            vim.cmd("RustLsp runnables")
          end, { desc = "Rust runnables", buffer = true })

          vim.keymap.set("n", "<leader>rt", function()
            vim.cmd("RustLsp testables")
          end, { desc = "Rust testables", buffer = true })

          vim.keymap.set("n", "<leader>rd", function()
            vim.cmd("RustLsp debuggables")
          end, { desc = "Rust debuggables", buffer = true })
        end,
      })
    end,
  },
}
