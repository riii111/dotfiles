-- Vim options configuration
vim.opt.relativenumber = true
vim.opt.number = true
vim.opt.spell = false
vim.opt.signcolumn = "yes"
vim.opt.wrap = false

-- Additional useful options
vim.opt.autoread = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.termguicolors = true
vim.opt.timeoutlen = 300
vim.opt.updatetime = 250

-- File synchronization for tmux + Claude Code workflow
vim.opt.autoread = true
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})

-- Auto-reload and re-lint when files change externally
vim.api.nvim_create_autocmd({ "FileChangedShellPost" }, {
  pattern = "*",
  callback = function()
    vim.notify("File changed on disk. Buffer reloaded!", vim.log.levels.INFO)
    -- Trigger LSP diagnostics refresh
    vim.schedule(function()
      -- Request fresh diagnostics from LSP servers
      for _, client in pairs(vim.lsp.get_active_clients()) do
        if client.server_capabilities.documentFormattingProvider then
          vim.lsp.buf.format({ async = true })
        end
      end
      vim.diagnostic.reset()
      vim.diagnostic.show()
    end)
  end,
})

-- Clipboard integration
vim.opt.clipboard = "unnamedplus"

-- Disable netrw (for file explorer)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

