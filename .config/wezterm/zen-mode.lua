local wezterm = require("wezterm")

-- Neovim zen-mode integration
-- When zen-mode.nvim sends ZEN_MODE user variable, WezTerm responds accordingly
wezterm.on("user-var-changed", function(window, pane, name, value)
	local overrides = window:get_config_overrides() or {}
	if name == "ZEN_MODE" then
		local incremental = value:find("+")
		local number_value = tonumber(value)

		-- Guard against non-numeric values
		if number_value == nil then
			return
		end

		if incremental ~= nil then
			-- Increase font size incrementally
			while number_value > 0 do
				window:perform_action(wezterm.action.IncreaseFontSize, pane)
				number_value = number_value - 1
			end
			overrides.enable_tab_bar = false
		elseif number_value < 0 then
			-- Reset to default (nil restores original config)
			window:perform_action(wezterm.action.ResetFontSize, pane)
			overrides.font_size = nil
			overrides.enable_tab_bar = nil
		else
			-- Set specific font size
			overrides.font_size = number_value
			overrides.enable_tab_bar = false
		end
	end
	window:set_config_overrides(overrides)
end)
