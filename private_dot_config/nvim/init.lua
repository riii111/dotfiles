-- Enable Lua module loader cache for faster startup
vim.loader.enable()

-- Polyfill: vim.tbl_flatten was removed in Nvim 0.12+
vim.tbl_flatten = function(t)
  return vim.iter(t):flatten(math.huge):totable()
end

-- Suppress Nvim 0.12.1 internal deprecation warnings (client.request etc.)
-- Neovim's own runtime calls deprecated LSP client methods; nothing we can fix.
local _orig_deprecate = vim.deprecate
vim.deprecate = function(name, ...)
  if name and name:match("^client%.") then return end
  return _orig_deprecate(name, ...)
end

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
end
vim.opt.rtp:prepend(lazypath)

-- Set leader keys before loading plugins
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load configuration
require("config.options")
require("config.keymaps")
require("config.autocmd")
require("config.lazy")

-- Apply colorscheme after lazy.nvim (fallback to custom-theme if not found)
local ok, _ = pcall(vim.cmd.colorscheme, "custom-theme-riii111")
if not ok then
	vim.cmd.colorscheme("custom-theme-riii111")
end

