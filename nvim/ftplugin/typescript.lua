local lsp_actions_ok, lsp_actions = pcall(require, "utils.lsp-actions")

if lsp_actions_ok then
  local opts = { buffer = true, silent = true }
  vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
  vim.keymap.set("n", "<D-S-r>", lsp_actions.typescript_refactor_menu, opts)
  vim.keymap.set("n", "<M-S-r>", lsp_actions.typescript_refactor_menu, opts)
end

vim.api.nvim_create_autocmd("BufWritePre", {
  pattern = { "*.js", "*.jsx", "*.ts", "*.tsx", "*.json", "*.jsonc" },
  callback = function()
    vim.lsp.buf.format({
      filter = function(client)
        return client.name == "null-ls"
      end,
      timeout_ms = 5000,
    })
  end,
})
