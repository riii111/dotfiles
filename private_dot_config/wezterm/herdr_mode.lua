local wezterm = require("wezterm")

local M = {}

M.prefix = "\x1b[59;5u"

M.modes = {
	main = "herdr_mode",
	copy = "herdr_copy_mode",
	passthrough = "herdr_passthrough_mode",
	resize = "herdr_resize_mode",
}

M.styles = {
	[M.modes.main] = {
		bg = "#2f4a38",
		fg = "#c8facc",
		label = " HERDR ",
	},
	[M.modes.copy] = {
		bg = "#2f4a38",
		fg = "#c8facc",
		label = " HERDR ",
	},
	[M.modes.passthrough] = {
		bg = "#2f4a38",
		fg = "#c8facc",
		label = " HERDR ",
	},
	[M.modes.resize] = {
		bg = "#4a3f24",
		fg = "#e6c384",
		label = " HERDR:RESIZE ",
	},
}

M.copy_exit_keys = {
	{ key = "Escape" },
	{ key = "q" },
	{ key = "y" },
	{ key = "Y", mods = "SHIFT" },
}

M.passthrough_exit_keys = {
	{ key = "Escape" },
	{ key = "Enter" },
	{ key = "q" },
}

local function window_key(window)
	local ok, id = pcall(function()
		return window:window_id()
	end)
	if ok and id ~= nil then
		return tostring(id)
	end
	return tostring(window)
end

function M.set_active_mode(window, mode)
	if not M.styles[mode] then
		return
	end

	wezterm.GLOBAL.herdr_active_modes = wezterm.GLOBAL.herdr_active_modes or {}
	wezterm.GLOBAL.herdr_active_modes[window_key(window)] = mode
end

function M.clear_active_mode(window)
	if not wezterm.GLOBAL.herdr_active_modes then
		return
	end
	wezterm.GLOBAL.herdr_active_modes[window_key(window)] = nil
end

function M.active_mode_for_tab(tab)
	if not tab.window_id or not wezterm.GLOBAL.herdr_active_modes then
		return nil
	end
	return wezterm.GLOBAL.herdr_active_modes[tostring(tab.window_id)]
end

function M.clear_all_modes()
	wezterm.GLOBAL.herdr_active_modes = {}
end

function M.foreground_process_name(pane)
	local ok, process = pcall(function()
		return pane:get_foreground_process_name()
	end)
	if not ok or not process then
		return ""
	end
	return process:match("([^/]+)$") or process
end

function M.is_herdr_pane(pane)
	return M.foreground_process_name(pane) == "herdr"
end

return M
