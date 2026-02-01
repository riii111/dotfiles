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

	-- Apply main highlights
	local highlights = require("custom-theme-riii111.highlights")
	highlights.apply()

	-- Apply bufferline overrides with slight delay to ensure bufferline is loaded
	vim.defer_fn(highlights.apply_bufferline_overrides, 50)

	-- P0 fix: Only reapply on ColorScheme change for THIS theme specifically
	vim.api.nvim_create_autocmd("ColorScheme", {
		pattern = THEME_NAME,
		callback = function()
			highlights.apply()
			vim.defer_fn(highlights.apply_bufferline_overrides, 10)
		end,
		group = vim.api.nvim_create_augroup("CustomThemeRiii111Apply", { clear = true }),
	})
end

return M
