-- Lua LSP bootstrap (runs on FileType=lua)
local root_markers = {
  ".git",
  ".luarc.json",
  ".luarc.jsonc",
  ".luacheckrc",
  "stylua.toml",
  "selene.toml",
}

local lua_settings = {
  Lua = {
    runtime = { version = "LuaJIT" },
    diagnostics = {
      globals = { "vim" },
      disable = { "redefined-local", "undefined-field", "missing-fields", "assign-type-mismatch" },
    },
    workspace = {
      checkThirdParty = false,
    },
    telemetry = { enable = false },
  },
}

vim.lsp.config("lua_ls", {
  cmd = { vim.fn.stdpath("data") .. "/mason/bin/lua-language-server" },
  filetypes = { "lua" },
  root_markers = root_markers,
  root_dir = function(bufnr, on_dir)
    local dir = vim.fs.root(bufnr, root_markers) or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
    on_dir(dir)
  end,
  workspace_required = false,
  settings = lua_settings,
  on_init = function(client)
    client.config.settings = vim.tbl_deep_extend("force", client.config.settings, lua_settings)
  end,
})

vim.lsp.enable("lua_ls")

-- Keymaps (IntelliJ-like actions)
local lsp_actions_ok, lsp_actions = pcall(require, "utils.lsp-actions")
if lsp_actions_ok then
  local opts = { buffer = true, silent = true }
  vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
  vim.keymap.set("n", "<D-S-r>", lsp_actions.lua_refactor_menu, opts)
  vim.keymap.set("n", "<M-S-r>", lsp_actions.lua_refactor_menu, opts)
end
