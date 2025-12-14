-- Async format on save utility
-- Provides non-blocking format-on-save for all languages

local M = {}

-- Formatter configuration per filetype
-- "null-ls" = use null-ls (ktlint, biome, stylua, etc.)
-- "<lsp-name>" = use specific LSP server (rust-analyzer, gopls, etc.)
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

-- Perform async format and auto-save after completion
function M.async_format(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local formatter_name = M.config[filetype]

  if not formatter_name then
    return
  end

  -- Find the formatter client
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = formatter_name })
  if #clients == 0 then
    return
  end

  local client = clients[1]
  local params = vim.lsp.util.make_formatting_params({})

  -- Send format request with callback
  client.request("textDocument/formatting", params, function(err, result)
    if err or not result then
      return
    end

    -- Apply edits and save
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.lsp.util.apply_text_edits(result, bufnr, client.offset_encoding)
        if vim.bo[bufnr].modified then
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("silent! update")
          end)
        end
      end
    end)
  end, bufnr)
end

return M
