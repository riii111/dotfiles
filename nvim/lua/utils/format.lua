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

-- opts.save: true → auto-save after format (default for on-save)
--            false → no save (for manual format)
function M.format(bufnr, opts)
  opts = opts or {}
  local save = opts.save ~= false

  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local formatter_name = M.config[vim.bo[bufnr].filetype]
  if not formatter_name then return end

  if vim.b[bufnr].async_format_running then return end

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = formatter_name })
  if #clients == 0 then return end
  local client = clients[1]
  local changedtick = vim.b[bufnr].changedtick

  vim.b[bufnr].async_format_running = true

  local ok, params = pcall(function()
    return vim.api.nvim_buf_call(bufnr, function()
      return vim.lsp.util.make_formatting_params({})
    end)
  end)
  if not ok then
    vim.b[bufnr].async_format_running = false
    return
  end

  client.request("textDocument/formatting", params, function(err, result)
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then return end
      vim.b[bufnr].async_format_running = false
      if err or not result then return end
      if vim.b[bufnr].changedtick ~= changedtick then return end

      vim.lsp.util.apply_text_edits(result, bufnr, client.offset_encoding or "utf-16")
      if save and vim.bo[bufnr].modified then
        vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent! update") end)
      end
    end)
  end, bufnr)
end

function M.async_format(bufnr)
  M.format(bufnr, { save = true })
end

return M
