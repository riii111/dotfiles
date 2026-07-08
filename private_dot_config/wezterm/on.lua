local wezterm = require("wezterm")
local act = wezterm.action
local io = require("io")
local os = require("os")
local herdr_mode = require("herdr_mode")

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

local function nvim_command()
	local home = os.getenv("HOME") or ""
	local path = home .. "/.nix-profile/bin/nvim"
	if file_exists(path) then
		return path
	end
	return "nvim"
end

-- Scrollback pager: open in nvim with ANSI colors
wezterm.on("open-scrollback-in-nvim", function(window, pane)
	local dims = pane:get_dimensions()
	local nlines = dims.scrollback_rows + dims.viewport_rows
	local text = pane:get_lines_as_escapes(nlines)

	local tmp = os.tmpname()
	local f, err = io.open(tmp, "w+")
	if not f then
		wezterm.log_error("scrollback pager: " .. (err or "unknown error"))
		return
	end
	f:write(text)
	f:flush()
	f:close()

	local marker = os.tmpname() .. "_done"
	local cursor = pane:get_cursor_position()
	local pager = wezterm.config_dir .. "/scrollback-pager.lua"

	local tab_id = window:active_tab():tab_id()
	window:perform_action(
		act.SpawnCommandInNewTab({
			args = {
				nvim_command(),
				"--clean",
				"-c",
				"let g:scrollback_cursor_x = " .. cursor.x,
				"-c",
				"let g:scrollback_marker = '" .. marker .. "'",
				"-c",
				"let g:scrollback_prev_tab = " .. tab_id,
				"-c",
				"luafile " .. pager,
				"-c",
				"terminal cat " .. tmp .. "; rm " .. tmp .. "; touch '" .. marker .. "'; tail -f /dev/null",
			},
		}),
		pane
	)
end)

-- Kanagawa Dragon background gradients
local KANAGAWA_BG_TRANSPARENT = {
	{
		source = {
			Gradient = {
				orientation = { Linear = { angle = -45.0 } },
				colors = { "#181616", "#1e1e22", "#221c24", "#1c1a20" },
			},
		},
		width = "100%",
		height = "100%",
		opacity = 0.70,
	},
	{
		source = {
			Gradient = {
				orientation = { Linear = { angle = 60.0 } },
				colors = { "#221e26", "#181616", "#261e24" },
			},
		},
		width = "100%",
		height = "100%",
		opacity = 0.45,
	},
}

local KANAGAWA_BG_OPAQUE = {
	{
		source = {
			Gradient = {
				orientation = { Linear = { angle = -45.0 } },
				colors = { "#0e0e10", "#141416", "#18141a", "#121014" },
			},
		},
		width = "100%",
		height = "100%",
		opacity = 0.82,
	},
	{
		source = {
			Gradient = {
				orientation = { Linear = { angle = 60.0 } },
				colors = { "#221e26", "#181616", "#261e24" },
			},
		},
		width = "100%",
		height = "100%",
		opacity = 0.25,
	},
}

local OPACITY_MIN = 0.35
local OPACITY_MAX = 1.0
local OPACITY_BASE = 0.7
local OPACITY_STEP = 0.05

local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

local function adjust_opacity(window, delta)
	local overrides = window:get_config_overrides() or {}
	local effective = window:effective_config()
	local current = overrides.window_background_opacity or effective.window_background_opacity or OPACITY_MAX
	local next_opacity = clamp(current + delta, OPACITY_MIN, OPACITY_MAX)
	local is_kanagawa = effective.color_scheme == "Kanagawa Dragon"

	overrides.window_background_opacity = next_opacity
	overrides.background = is_kanagawa
			and (next_opacity >= OPACITY_BASE and KANAGAWA_BG_OPAQUE or KANAGAWA_BG_TRANSPARENT)
		or nil

	window:set_config_overrides(overrides)
end

wezterm.on("decrease-opacity", function(window, _)
	adjust_opacity(window, -OPACITY_STEP)
end)

wezterm.on("increase-opacity", function(window, _)
	adjust_opacity(window, OPACITY_STEP)
end)

-- Toggle background blur
wezterm.on("toggle-blur", function(window, _)
	local overrides = window:get_config_overrides() or {}
	if overrides.macos_window_background_blur ~= 0 then
		overrides.macos_window_background_blur = 0
	else
		overrides.macos_window_background_blur = nil
	end
	window:set_config_overrides(overrides)
end)

-- Tab title: show process name instead of shell-set title
wezterm.on("format-tab-title", function(tab)
	local pane = tab.active_pane
	local process = pane.foreground_process_name or ""
	local name = process:match("([^/]+)$") or pane.title

	local style = tab.is_active and herdr_mode.styles[herdr_mode.active_mode_for_tab(tab)] or nil
	if style then
		return {
			{ Background = { Color = style.bg } },
			{ Foreground = { Color = style.fg } },
			{ Attribute = { Intensity = "Bold" } },
			{ Text = " " .. name .. " " },
		}
	end

	return " " .. name .. " "
end)
