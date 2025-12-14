-- Async format on save (non-blocking)
--
-- Sync:  :w → format (BLOCKED) → save
-- Async: :w → save → format (background) → auto-save

local M = {}

M.config = {
  kotlin = "null-ls",
  python = "null-ls",
  lua = "null-ls",
  typescript = "null-ls",
  typescriptreact = "null-ls",
  javascript = "null-ls",
  javascriptreact = "null-ls",
  json = "null-ls",
  jsonc = "null-ls",
  rust = "rust-analyzer",
  go = "gopls",
  terraform = "null-ls",
  hcl = "null-ls",
  ["terraform-vars"] = "null-ls",
}

local function find_client(bufnr, names)
  if type(names) == "string" then names = { names } end
  for _, name in ipairs(names) do
    local clients = vim.lsp.get_clients({ bufnr = bufnr, name = name })
    if #clients > 0 then return clients[1] end
  end
end

function M.async_format(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local formatter_names = M.config[vim.bo[bufnr].filetype]
  if not formatter_names then return end

  -- Prevent re-entry loop
  if vim.b[bufnr].async_format_running then return end

  local client = find_client(bufnr, formatter_names)
  if not client then return end
  local changedtick = vim.b[bufnr].changedtick

  vim.b[bufnr].async_format_running = true
  local params = vim.api.nvim_buf_call(bufnr, function()
    return vim.lsp.util.make_formatting_params({})
  end)

  client.request("textDocument/formatting", params, function(err, result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      vim.b[bufnr].async_format_running = false
      if err or not result then return end
      if vim.b[bufnr].changedtick ~= changedtick then return end

      vim.lsp.util.apply_text_edits(result, bufnr, client.offset_encoding or "utf-16")
      if vim.bo[bufnr].modified then
        vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! update") end)
      end
    end)
  end, bufnr)
end

return M
