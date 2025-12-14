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
}

function M.async_format(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local formatter_name = M.config[vim.bo[bufnr].filetype]
  if not formatter_name then return end

  -- Prevent re-entry loop
  if vim.b[bufnr].async_format_running then return end

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = formatter_name })
  if #clients == 0 then return end

  local client = clients[1]
  local changedtick = vim.b[bufnr].changedtick

  vim.b[bufnr].async_format_running = true
  client.request("textDocument/formatting", vim.lsp.util.make_formatting_params({}), function(err, result)
    vim.schedule(function()
      vim.b[bufnr].async_format_running = false
      if err or not result then return end
      -- Skip if buffer changed during format
      if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].changedtick ~= changedtick then return end

      vim.lsp.util.apply_text_edits(result, bufnr, client.offset_encoding or "utf-16")
      if vim.bo[bufnr].modified then
        vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! update") end)
      end
    end)
  end, bufnr)
end

return M
