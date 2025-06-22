-- Vim options configuration
vim.opt.relativenumber = false
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

-- Clipboard integration
vim.opt.clipboard = "unnamedplus"

-- Disable netrw (for neo-tree)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1