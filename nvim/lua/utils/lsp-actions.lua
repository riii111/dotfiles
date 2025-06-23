local M = {}

function M.smart_code_action()
  vim.lsp.buf.code_action({
    context = { only = { "quickfix", "refactor" } },
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
    if not choice then return end

    local cmd = choice:match("^(RustLsp [^-]+)")
    vim.cmd(cmd:gsub("RustLsp ", "RustLsp "))
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
    if choice then
      local cmd = choice:match("^(%S+)")
      vim.cmd(cmd)
    end
  end)
end

function M.language_specific_code_action()
  local filetype = vim.bo.filetype

  vim.lsp.buf.code_action({
    context = { only = { "quickfix", "refactor" } },
    apply = false,
  }, function(actions)
    if actions and #actions > 0 then
      if #actions == 1 then
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
        local has_lspsaga, lspsaga = pcall(require, "lspsaga")
        if has_lspsaga then
          vim.cmd("Lspsaga code_action")
        else
          vim.notify("No code actions available", vim.log.levels.INFO)
        end
      end
    end
  end)
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
  }

  vim.ui.select(options, {
    prompt = "Select Refactoring:",
  }, function(choice)
    if not choice then return end

    local cmd = choice:match("^(RustLsp [^-]+)")
    vim.cmd(cmd:gsub("RustLsp ", "RustLsp "))
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
    "GoRename - Rename symbol",
  }

  vim.ui.select(options, {
    prompt = "Select Refactoring:",
    layout = "cursor",
  }, function(choice)
    if not choice then return end

    local cmd = choice:match("^(%S+)")
    if cmd == "GoAddTag" then
      local tag = choice:match("(%w+)$")
      vim.cmd("GoAddTag " .. tag)
    else
      vim.cmd(cmd)
    end
  end)
end

return M

