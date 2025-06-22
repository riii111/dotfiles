return {
  {
    "mrcjkb/rustaceanvim",
    version = "^5",
    lazy = false,
    config = function()
      -- IntelliJ IDEA-style shortcuts for Rust
      local function rust_refactor_menu()
        local options = {
          "RustLsp expandMacro - Expand macro",
          "RustLsp moveItem up - Move item up",
          "RustLsp moveItem down - Move item down",
          "RustLsp ssr - Structural search replace",
          "RustLsp joinLines - Join lines",
          "RustLsp hover actions - Hover actions",
          "RustLsp openCargo - Open Cargo.toml",
          "RustLsp parentModule - Go to parent module",
        }
        
        vim.ui.select(options, {
          prompt = "Select Refactoring:",
        }, function(choice)
          if not choice then return end
          
          local cmd = choice:match("^(RustLsp [^-]+)")
          vim.cmd(cmd:gsub("RustLsp ", "RustLsp "))
        end)
      end
      
      local function rust_quick_actions()
        local options = {
          "RustLsp codeAction - Code actions",
          "RustLsp explainError - Explain error",  
          "RustLsp renderDiagnostic - Show diagnostic",
          "RustLsp relatedDiagnostics - Related diagnostics",
          "RustLsp hover actions - Hover actions",
        }
        
        vim.ui.select(options, {
          prompt = "Rust Quick Fix:",
        }, function(choice)
          if not choice then return end
          
          local cmd = choice:match("^(RustLsp [^-]+)")
          vim.cmd(cmd:gsub("RustLsp ", "RustLsp "))
        end)
      end
      
      -- Set up IntelliJ IDEA-style keymaps for Rust files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "rust",
        callback = function()
          local opts = { buffer = true, silent = true }
          
          -- Alt+Enter: Code actions (LSP + Rust-specific)
          vim.keymap.set("n", "<M-CR>", function()
            -- Try LSP code actions first
            vim.lsp.buf.code_action({
              context = { only = { "quickfix", "refactor" } },
              apply = false,
            }, function(actions)
              if actions and #actions > 0 then
                vim.lsp.buf.code_action()
              else
                -- Fallback to Rust-specific quick fixes
                rust_quick_actions()
              end
            end)
          end, opts)
          
          -- Cmd+Shift+R: Refactor menu
          vim.keymap.set("n", "<D-S-r>", rust_refactor_menu, opts)
          
          -- Additional Rust shortcuts
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