-- Lua LSP bootstrap (runs on FileType=lua)
local root_markers = {
  ".git",
  ".luarc.json",
  ".luarc.jsonc",
  ".luacheckrc",
  "stylua.toml",
  "selene.toml",
}

if not vim.lsp.config["lua_ls"] then
  vim.lsp.config("lua_ls", {
    cmd = { vim.fn.stdpath("data") .. "/mason/bin/lua-language-server" },
    filetypes = { "lua" },
    root_markers = root_markers,
    root_dir = function(bufnr, on_dir)
      local dir = vim.fs.root(bufnr, root_markers) or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
      on_dir(dir)
    end,
    workspace_required = false,
    settings = {
      Lua = {
        runtime = { version = "LuaJIT" },
        diagnostics = { globals = { "vim" } },
        workspace = { checkThirdParty = false },
        telemetry = { enable = false },
      },
    },
  })
end

if not vim.lsp.is_enabled("lua_ls") then
  vim.lsp.enable("lua_ls")
end
