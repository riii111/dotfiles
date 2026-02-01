local M = {}

local THEME_NAME = "custom-theme-riii111"

--- Optional setup for configuration
---@param opts table|nil
function M.setup(opts)
	-- Reserved for future configuration options
	_ = opts
end

--- Returns the color palette for external use
---@return table
function M.palette()
	return require("custom-theme-riii111.palette")
end

--- Check if this theme is currently active
---@return boolean
function M.is_active()
	return vim.g.colors_name == THEME_NAME
end

--- Load and apply the colorscheme
function M.load()
	-- Set colorscheme name
	vim.g.colors_name = THEME_NAME

	-- Ensure 24-bit colors (other themes like pixel.nvim may disable this)
	vim.opt.termguicolors = true

	-- Apply main highlights
	local highlights = require("custom-theme-riii111.highlights")
	highlights.apply()

	-- Apply bufferline overrides after plugins are loaded
	vim.api.nvim_create_autocmd("User", {
		pattern = "VeryLazy",
		once = true,
		callback = highlights.apply_bufferline_overrides,
		group = vim.api.nvim_create_augroup("CustomThemeBufferlineInit", { clear = true }),
	})

	-- Reapply on ColorScheme change for THIS theme specifically
	vim.api.nvim_create_autocmd("ColorScheme", {
		pattern = THEME_NAME,
		callback = function()
			highlights.apply()
			highlights.apply_bufferline_overrides()
		end,
		group = vim.api.nvim_create_augroup("CustomThemeRiii111Apply", { clear = true }),
	})
end

return M
