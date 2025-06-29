local M = {}

local function get_current_line_diagnostics()
  return vim.diagnostic.get(0, { lnum = vim.fn.line('.') - 1 })
end

local function create_code_action_context(only_types)
  return {
    only = only_types or { "quickfix", "refactor" },
    diagnostics = get_current_line_diagnostics()
  }
end

local function execute_menu_choice(choice, cmd_patterns)
  if not choice then return end

  for pattern, handler in pairs(cmd_patterns) do
    if choice:match(pattern) then
      handler(choice)
      return
    end
  end
end

function M.smart_code_action()
  vim.lsp.buf.code_action({
    context = create_code_action_context(),
    apply = true,
  })
end

function M.rust_quick_actions()
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
    execute_menu_choice(choice, {
      ["^(RustLsp [^-]+)"] = function(c) vim.cmd(c:match("^(RustLsp [^-]+)")) end
    })
  end)
end

function M.go_quick_actions()
  local go_actions = {
    "GoIfErr - Add error handling",
    "GoFillStruct - Fill struct",
    "GoImpl - Implement interface",
  }

  vim.ui.select(go_actions, {
    prompt = "Go Quick Fix:",
    layout = "cursor",
  }, function(choice)
    execute_menu_choice(choice, {
      ["^(%S+)"] = function(c) vim.cmd(c:match("^(%S+)")) end
    })
  end)
end

function M.language_specific_code_action()
  local filetype = vim.bo.filetype

  local params = vim.lsp.util.make_position_params(0, 'utf-16')
  local actions = vim.lsp.buf_request_sync(0, 'textDocument/codeAction', {
    textDocument = vim.lsp.util.make_text_document_params(0),
    range = { start = params.position, ['end'] = params.position },
    context = create_code_action_context()
  }, 1000)

  local valid_actions = {}
  if actions then
    for _, client_actions in pairs(actions) do
      if client_actions.result then
        for _, action in ipairs(client_actions.result) do
          table.insert(valid_actions, action)
        end
      end
    end
  end

  if valid_actions and #valid_actions > 0 then
    if #valid_actions == 1 then
      vim.lsp.buf.code_action({ apply = true })
    else
      vim.lsp.buf.code_action()
    end
  else
    if filetype == "rust" then
      M.rust_quick_actions()
    elseif filetype == "go" then
      M.go_quick_actions()
    else
      local generic_options = {
        "Rename - Rename symbol",
        "Code Action - Show available actions",
      }

      vim.ui.select(generic_options, {
        prompt = "Select Action:",
      }, function(choice)
        execute_menu_choice(choice, {
          ["^Rename"] = function() vim.lsp.buf.rename() end,
          ["."] = function()
            local has_lspsaga = pcall(require, "lspsaga")
            if has_lspsaga then
              vim.cmd("Lspsaga code_action")
            else
              vim.lsp.buf.code_action()
            end
          end
        })
      end)
    end
  end
end

function M.rust_refactor_menu()
  local options = {
    "RustLsp expandMacro - Expand macro",
    "RustLsp moveItem up - Move item up",
    "RustLsp moveItem down - Move item down",
    "RustLsp ssr - Structural search replace",
    "RustLsp joinLines - Join lines",
    "RustLsp hover actions - Hover actions",
    "RustLsp openCargo - Open Cargo.toml",
    "RustLsp parentModule - Go to parent module",
    "Rename - Rename symbol",
  }

  vim.ui.select(options, {
    prompt = "Select Refactoring:",
  }, function(choice)
    execute_menu_choice(choice, {
      ["^Rename"] = function() vim.lsp.buf.rename() end,
      ["^(RustLsp [^-]+)"] = function(c) vim.cmd(c:match("^(RustLsp [^-]+)")) end
    })
  end)
end

function M.go_refactor_menu()
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
    "Rename - Rename symbol",
  }

  vim.ui.select(options, {
    prompt = "Select Refactoring:",
    layout = "cursor",
  }, function(choice)
    execute_menu_choice(choice, {
      ["^GoAddTag"] = function(c)
        local tag = c:match("(%w+)$")
        vim.cmd("GoAddTag " .. tag)
      end,
      ["^Rename"] = function() vim.lsp.buf.rename() end,
      ["^(%S+)"] = function(c) vim.cmd(c:match("^(%S+)")) end
    })
  end)
end

return M

