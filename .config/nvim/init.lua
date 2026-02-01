-- Enable Lua module loader cache for faster startup
vim.loader.enable()

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
-- local ok, _ = pcall(vim.cmd.colorscheme, "rose-pine-moon")
local ok, _ = pcall(vim.cmd.colorscheme, "custom-theme-riii111")
if not ok then
	vim.cmd.colorscheme("custom-theme-riii111")
end
