-- Disable unused providers for faster startup
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0

-- Disable unused default plugins
vim.g.loaded_gzip = 1
vim.g.loaded_tar = 1
vim.g.loaded_tarPlugin = 1
vim.g.loaded_zip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_getscript = 1
vim.g.loaded_getscriptPlugin = 1
vim.g.loaded_vimball = 1
vim.g.loaded_vimballPlugin = 1
vim.g.loaded_matchit = 1
vim.g.loaded_2html_plugin = 1
vim.g.loaded_logiPat = 1
vim.g.loaded_rrhelper = 1

-- Add full-width bracket pairs for % jump
vim.opt.matchpairs:append({ "（:）", "「:」", "『:』", "【:】", "［:］", "＜:＞" })

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

-- Auto commands for file change detection
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
  pattern = "*",
  callback = function()
    if vim.fn.mode() ~= "c" then
      vim.cmd("checktime")
    end
  end,
})

-- Notify LSP about buffer content change (used after external file changes)
local function notify_lsp_buffer_changed(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(bufnr)
  local filetype = vim.bo[bufnr].filetype

  for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    -- Close and reopen to force full content sync
    client.notify("textDocument/didClose", {
      textDocument = { uri = uri }
    })

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    client.notify("textDocument/didOpen", {
      textDocument = {
        uri = uri,
        languageId = filetype,
        version = (vim.lsp.util.buf_versions[bufnr] or 0) + 1,
        text = table.concat(lines, "\n")
      }
    })
  end
end

-- Auto-reload and notify LSP when files change externally
vim.api.nvim_create_autocmd({ "FileChangedShellPost" }, {
  pattern = "*",
  callback = function()
    vim.notify("File changed on disk. Buffer reloaded!", vim.log.levels.INFO)
    vim.schedule(function()
      notify_lsp_buffer_changed()
    end)
  end,
})

-- Fix LSP diagnostics UI not updating after publishDiagnostics (Neovim issue #30385)
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
  require("vim.lsp.diagnostic").on_publish_diagnostics(err, result, ctx, config)
  vim.schedule(function()
    vim.diagnostic.show()
  end)
end

-- Clipboard integration
-- Check if running inside tmux
if vim.env.TMUX then
  -- Use OSC 52 for clipboard operations in tmux
  vim.g.clipboard = {
    name = 'OSC 52',
    copy = {
      ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
      ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
    },
    paste = {
      ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
      ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    },
  }
else
  vim.opt.clipboard = "unnamedplus"
end

-- Disable netrw (for file explorer)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- Disable winbar breadcrumbs
vim.o.winbar = ""

