local wezterm = require("wezterm")
local act = wezterm.action

local keys = {
	---------------------------------------------------------------
	-- Pane: Split (same as Ghostty)
	---------------------------------------------------------------
	{ key = "d", mods = "CMD", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ key = "d", mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },

	---------------------------------------------------------------
	-- Pane: Navigation (Cmd+[ / Cmd+] for prev/next)
	---------------------------------------------------------------
	{ key = "[", mods = "CMD", action = act.ActivatePaneDirection("Prev") },
	{ key = "]", mods = "CMD", action = act.ActivatePaneDirection("Next") },

	---------------------------------------------------------------
	-- Forward to Neovim (Cmd+Arrow / Cmd+Opt+Arrow)
	---------------------------------------------------------------
	{ key = "DownArrow", mods = "CMD", action = act.SendKey({ key = "DownArrow", mods = "CTRL|SHIFT" }) },
	{ key = "RightArrow", mods = "CMD", action = act.SendKey({ key = "RightArrow", mods = "CTRL|SHIFT" }) },
	{ key = "LeftArrow", mods = "ALT", action = act.SendString("\x1bb") },
	{ key = "RightArrow", mods = "ALT", action = act.SendString("\x1bf") },
	{ key = "LeftArrow", mods = "CMD|ALT", action = act.SendKey({ key = "LeftArrow", mods = "ALT|SHIFT" }) },
	{ key = "RightArrow", mods = "CMD|ALT", action = act.SendKey({ key = "RightArrow", mods = "ALT|SHIFT" }) },

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
	{ key = "Enter", mods = "CMD", action = act.ToggleFullScreen },
	{ key = "Enter", mods = "ALT", action = act.SendKey({ key = "Enter", mods = "ALT" }) },
	-- Shift+Enter: send CSI-u sequence explicitly (WezTerm doesn't advertise
	-- extkeys to tmux, so protocol negotiation fails; this is a workaround)
	{ key = "Enter", mods = "SHIFT", action = act.SendString("\x1b[13;2u") },

	---------------------------------------------------------------
	-- Tab
	---------------------------------------------------------------
	{ key = "t", mods = "CMD", action = act.SpawnTab("CurrentPaneDomain") },
	{ key = "w", mods = "CMD|SHIFT", action = act.CloseCurrentTab({ confirm = true }) },

	---------------------------------------------------------------
	-- Toggle opacity / blur
	---------------------------------------------------------------
	{ key = "o", mods = "CMD|CTRL", action = act.EmitEvent("toggle-opacity") },
	{ key = "b", mods = "CMD|CTRL", action = act.EmitEvent("toggle-blur") },


	---------------------------------------------------------------
	-- Select All: enter CopyMode and select text above cursor
	---------------------------------------------------------------
	{
		key = "a",
		mods = "CMD",
		action = wezterm.action_callback(function(window, pane)
			window:perform_action(act.ActivateCopyMode, pane)
			window:perform_action(act.CopyMode({ SetSelectionMode = "Cell" }), pane)
			window:perform_action(act.CopyMode("MoveToScrollbackTop"), pane)
		end),
	},

	---------------------------------------------------------------
	-- Pass Cmd keys to Neovim as Ctrl keys
	-- Only override keys that don't conflict with WezTerm functions
	-- For other Ctrl combinations, just press Ctrl directly
	---------------------------------------------------------------
	{ key = "p", mods = "CMD", action = act.SendKey({ key = "p", mods = "CTRL" }) },
	{ key = "u", mods = "CMD", action = act.SendKey({ key = "u", mods = "CTRL" }) },
	{ key = "e", mods = "CMD", action = act.SendKey({ key = "e", mods = "CTRL" }) },

	-- Cmd+F for buffer search in Neovim (disable WezTerm's search)
	{ key = "f", mods = "CMD", action = act.SendKey({ key = "f", mods = "ALT" }) },

	-- Cmd+Shift combinations (for Telescope etc.)
	{ key = "f", mods = "CMD|SHIFT", action = act.SendKey({ key = "f", mods = "CTRL|SHIFT" }) },
	{ key = "p", mods = "CMD|SHIFT", action = act.SendKey({ key = "p", mods = "CTRL|SHIFT" }) },

	-- Cmd+Shift+R → Alt+Shift+R (Neovim refactor menu via <M-S-r> fallback)
	{ key = "r", mods = "CMD|SHIFT", action = act.SendKey({ key = "r", mods = "ALT|SHIFT" }) },

	---------------------------------------------------------------
	-- JIS keyboard: Option+¥ for | and \
	---------------------------------------------------------------
	{ key = "¥", mods = "ALT", action = act.SendString("|") },
	{ key = "|", mods = "ALT|SHIFT", action = act.SendString("\\") },


}

return keys
