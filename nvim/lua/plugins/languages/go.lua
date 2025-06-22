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
        goimports = "gopls",
        fillstruct = "gopls",
        dap_debug = false,
        textobjects = true,
        lsp_cfg = {
          capabilities = {
            textDocument = {
              codeAction = {
                dynamicRegistration = true,
                codeActionLiteralSupport = {
                  codeActionKind = {
                    valueSet = {
                      "quickfix",
                      "refactor",
                      "refactor.extract",
                      "refactor.inline",
                      "refactor.rewrite",
                      "source",
                      "source.organizeImports",
                    },
                  },
                },
              },
            },
          },
          settings = {
            gopls = {
              hints = {
                assignVariableTypes = false,
                compositeLiteralFields = false,
                compositeLiteralTypes = false,
                constantValues = false,
                functionTypeParameters = false,
                parameterNames = false,
                rangeVariableTypes = false,
              },
            },
          },
        },
      })
      
      -- IntelliJ IDEA-style shortcuts for Go
      local function go_refactor_menu()
        local options = {
          "GoIfErr - Add if err != nil",
          "GoFillStruct - Fill struct fields",
          "GoFixPlurals - Fix plural parameters",
          "GoAddTag json - Add JSON tags",
          "GoAddTag yaml - Add YAML tags",
          "GoRmTag - Remove tags",
          "GoImpl - Implement interface",
          "GoGenReturn - Generate return statement",
          "GoCmt - Add comments",
          "GoRename - Rename symbol",
        }
        
        vim.ui.select(options, {
          prompt = "Select Refactoring:",
          layout = "cursor",
        }, function(choice)
          if not choice then return end
          
          local text = choice
          local cmd = text:match("^(%S+)")
          if cmd == "GoAddTag" then
            local tag = text:match("(%w+)$")
            vim.cmd("GoAddTag " .. tag)
          else
            vim.cmd(cmd)
          end
        end)
      end
      
      -- Set up IntelliJ IDEA-style keymaps for Go files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "go",
        callback = function()
          local opts = { buffer = true, silent = true }
          
          -- Alt+Enter: Code actions (LSP + Go-specific)
          vim.keymap.set("n", "<M-CR>", function()
            -- Try LSP code actions first
            local has_actions = false
            vim.lsp.buf.code_action({
              context = { only = { "quickfix", "refactor" } },
              apply = false,
            }, function(actions)
              if actions and #actions > 0 then
                has_actions = true
                vim.lsp.buf.code_action()
              else
                -- Fallback to Go-specific quick fixes
                local go_actions = {
                  "GoIfErr - Add error handling",
                  "GoFillStruct - Fill struct",
                  "GoImpl - Implement interface",
                }
                
                vim.ui.select(go_actions, {
                  prompt = "Go Quick Fix:",
                  layout = "cursor",
                }, function(choice)
                  if choice then
                    local text = choice
                    local cmd = text:match("^(%S+)")
                    vim.cmd(cmd)
                  end
                end)
              end
            end)
          end, opts)
          
          -- Cmd+Shift+R: Refactor menu
          vim.keymap.set("n", "<D-S-r>", go_refactor_menu, opts)
        end,
      })
    end,
    event = {"CmdlineEnter"},
    ft = {"go", 'gomod'},
    build = ':lua require("go.install").update_all_sync()'
  },
}