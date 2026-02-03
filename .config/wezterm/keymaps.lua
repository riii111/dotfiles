local wezterm = require("wezterm")
local act = wezterm.action

local keys = {
	---------------------------------------------------------------
	-- Pane: Split (same as Ghostty)
	---------------------------------------------------------------
	{ key = "d", mods = "CMD", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "d", mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

	---------------------------------------------------------------
	-- Pane: Navigation (same as Ghostty)
	---------------------------------------------------------------
	{ key = "[", mods = "CMD", action = act.ActivatePaneDirection("Prev") },
	{ key = "]", mods = "CMD", action = act.ActivatePaneDirection("Next") },
	{ key = "LeftArrow", mods = "CMD|ALT", action = act.ActivatePaneDirection("Left") },
	{ key = "RightArrow", mods = "CMD|ALT", action = act.ActivatePaneDirection("Right") },
	{ key = "UpArrow", mods = "CMD|ALT", action = act.ActivatePaneDirection("Up") },
	{ key = "DownArrow", mods = "CMD|ALT", action = act.ActivatePaneDirection("Down") },

	---------------------------------------------------------------
	-- Pane: Resize (Cmd+Opt+hjkl)
	---------------------------------------------------------------
	{ key = "h", mods = "CMD|ALT", action = act.AdjustPaneSize({ "Left", 5 }) },
	{ key = "j", mods = "CMD|ALT", action = act.AdjustPaneSize({ "Down", 5 }) },
	{ key = "k", mods = "CMD|ALT", action = act.AdjustPaneSize({ "Up", 5 }) },
	{ key = "l", mods = "CMD|ALT", action = act.AdjustPaneSize({ "Right", 5 }) },

	---------------------------------------------------------------
	-- Pane: Close / Zoom
	---------------------------------------------------------------
	{ key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) },
	{ key = "z", mods = "CMD", action = act.TogglePaneZoomState },

	---------------------------------------------------------------
	-- Tab
	---------------------------------------------------------------
	{ key = "t", mods = "CMD", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "CMD|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },

	-- Tab switching with Leader + number
	{ key = "1", mods = "LEADER", action = act.ActivateTab(0) },
	{ key = "2", mods = "LEADER", action = act.ActivateTab(1) },
	{ key = "3", mods = "LEADER", action = act.ActivateTab(2) },
	{ key = "4", mods = "LEADER", action = act.ActivateTab(3) },
	{ key = "5", mods = "LEADER", action = act.ActivateTab(4) },
	{ key = "6", mods = "LEADER", action = act.ActivateTab(5) },
	{ key = "7", mods = "LEADER", action = act.ActivateTab(6) },
	{ key = "8", mods = "LEADER", action = act.ActivateTab(7) },
	{ key = "9", mods = "LEADER", action = act.ActivateTab(8) },

	---------------------------------------------------------------
	-- Toggle opacity / blur
	---------------------------------------------------------------
	{ key = "o", mods = "CMD|CTRL", action = act.EmitEvent("toggle-opacity") },
	{ key = "b", mods = "CMD|CTRL", action = act.EmitEvent("toggle-blur") },

	---------------------------------------------------------------
	-- Quick select (like tmux copy mode)
	---------------------------------------------------------------
	{ key = "Space", mods = "LEADER", action = act.QuickSelect },

	---------------------------------------------------------------
	-- Pass Cmd keys to Neovim as Ctrl keys
	-- Only override keys that don't conflict with WezTerm functions
	-- For other Ctrl combinations, just press Ctrl directly
	---------------------------------------------------------------
	{ key = "p", mods = "CMD", action = act.SendKey({ key = "p", mods = "CTRL" }) },
	{ key = "u", mods = "CMD", action = act.SendKey({ key = "u", mods = "CTRL" }) },
	{ key = "e", mods = "CMD", action = act.SendKey({ key = "e", mods = "CTRL" }) },

	-- Cmd+Shift combinations (for Telescope etc.)
	{ key = "f", mods = "CMD|SHIFT", action = act.SendKey({ key = "f", mods = "CTRL|SHIFT" }) },
	{ key = "p", mods = "CMD|SHIFT", action = act.SendKey({ key = "p", mods = "CTRL|SHIFT" }) },

	---------------------------------------------------------------
	-- JIS keyboard: Option+¥ for | and \
	---------------------------------------------------------------
	{ key = "¥", mods = "ALT", action = act.SendString("|") },
	{ key = "|", mods = "ALT|SHIFT", action = act.SendString("\\") },


	---------------------------------------------------------------
	-- Theme switcher (Leader + t)
	---------------------------------------------------------------
	{
		key = "t",
		mods = "LEADER",
		action = act.InputSelector({
			title = "Color Scheme",
			choices = {
				{ label = "Kanagawa Dragon" },
				{ label = "Catppuccin Mocha" },
				{ label = "Catppuccin Macchiato" },
				{ label = "Catppuccin Frappe" },
				{ label = "Catppuccin Latte" },
				{ label = "duckbones" },
			},
			action = wezterm.action_callback(function(window, _, _, label)
				if label then
					local schemes = wezterm.get_builtin_color_schemes()
					schemes["Kanagawa Dragon"] = require("colors.kanagawa_dragon").colors
					local scheme = schemes[label]
					local bg = scheme and scheme.background or "#181616"
					window:set_config_overrides({
						color_scheme = label,
						window_background_gradient = { colors = { bg } },
						window_frame = {
							active_titlebar_bg = bg,
							inactive_titlebar_bg = bg,
						},
					})
				end
			end),
		}),
	},
}

return keys
