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

-- Right status: repo, git ref, flags, time
local SEP = "\u{e0b3}"
local STATUS_BG = "#1f1f28"
local git_info_by_pane = {}
local herdr_git_info_by_pane_id = {}
local herdr_focused_git_info = nil
local herdr_focused_payload_at = nil
local GIT_INFO_MAX_ENTRIES = 200
local GIT_INFO_MAX_AGE_SECONDS = 3600

local FLAG_BADGES = {
	R = { text = " REBASE", color = "#ff9e64" },
	C = { text = " PICK", color = "#ff9e64" },
}

local function get_foreground_process_name(pane)
	local ok, process = pcall(function()
		return pane:get_foreground_process_name()
	end)
	if not ok or not process then
		return ""
	end
	return (process:match("([^/]+)$") or process)
end

local function is_herdr_pane(pane)
	return get_foreground_process_name(pane) == "herdr"
end

local function pane_key(pane)
	local ok, pane_id = pcall(function()
		return pane:pane_id()
	end)
	if ok and pane_id ~= nil then
		return tostring(pane_id)
	end
	return tostring(pane)
end

local function split_tabs(value)
	local fields = {}
	for field in (value .. "\t"):gmatch("([^\t]*)\t") do
		table.insert(fields, field)
	end
	return fields
end

local function prune_git_info_table(entries, now)
	local count = 0
	local oldest_key = nil
	local oldest_at = nil

	for key, entry in pairs(entries) do
		local seen_at = entry.seen_at or 0
		if now - seen_at > GIT_INFO_MAX_AGE_SECONDS then
			entries[key] = nil
		else
			count = count + 1
			if not oldest_at or seen_at < oldest_at then
				oldest_key = key
				oldest_at = seen_at
			end
		end
	end

	if count > GIT_INFO_MAX_ENTRIES and oldest_key then
		entries[oldest_key] = nil
	end
end

local function parse_git_payload(value)
	if not value or value == "" then
		return nil
	end

	local fields = split_tabs(value)
	if fields[1] ~= "wezgit1" then
		return nil
	end

	local at = tonumber(fields[2])
	if not at then
		return nil
	end

	local present = fields[4] == "1"
	local info = {
		at = at,
		cwd = fields[3] or "",
		present = present,
		repo = present and fields[5] or nil,
		ref = present and fields[6] or nil,
		flags = fields[7] or "",
		herdr_pane_id = fields[8] or "",
	}

	if present and (not info.repo or info.repo == "" or not info.ref or info.ref == "") then
		return nil
	end

	return info
end

local function parse_herdr_payload(value)
	if not value or value == "" then
		return nil
	end

	local fields = split_tabs(value)
	if fields[1] ~= "herdrgit1" then
		return nil
	end

	local at = tonumber(fields[2])
	if not at then
		return nil
	end

	local present = fields[5] == "1"
	local info = {
		at = at,
		herdr_pane_id = fields[3] or "",
		cwd = fields[4] or "",
		present = present,
		repo = present and fields[6] or nil,
		ref = present and fields[7] or nil,
		flags = fields[8] or "",
	}

	if present and (not info.repo or info.repo == "" or not info.ref or info.ref == "") then
		return nil
	end

	return info
end

local function accept_git_info_for_pane(pane, info)
	if not info then
		return
	end

	local now = os.time()
	info.seen_at = now
	prune_git_info_table(git_info_by_pane, now)
	prune_git_info_table(herdr_git_info_by_pane_id, now)

	if is_herdr_pane(pane) then
		if not info.herdr_pane_id or info.herdr_pane_id == "" then
			return
		end
		local existing = herdr_git_info_by_pane_id[info.herdr_pane_id]
		if existing and info.at < existing.at then
			return
		end
		herdr_git_info_by_pane_id[info.herdr_pane_id] = info
		return
	end

	local key = pane_key(pane)
	local existing = git_info_by_pane[key]
	if existing and info.at < existing.at then
		return
	end
	git_info_by_pane[key] = info
end

local function herdr_cache_path()
	local cache_home = os.getenv("XDG_CACHE_HOME")
	if not cache_home or cache_home == "" then
		local home = os.getenv("HOME") or ""
		cache_home = home .. "/.cache"
	end
	return cache_home .. "/wezterm/herdr-git-info"
end

local function read_herdr_focused_git_info()
	local path = herdr_cache_path()
	local f = io.open(path, "r")
	if not f then
		return herdr_focused_git_info
	end

	local value = f:read("*l")
	f:close()
	local info = parse_herdr_payload(value)
	if not info then
		return herdr_focused_git_info
	end

	if not herdr_focused_payload_at or info.at >= herdr_focused_payload_at then
		herdr_focused_payload_at = info.at
		herdr_focused_git_info = info
	end
	return herdr_focused_git_info
end

local function get_git_info_from_user_vars(pane)
	local user_vars = pane:get_user_vars() or {}
	accept_git_info_for_pane(pane, parse_git_payload(user_vars.WEZ_GIT_INFO))
	return git_info_by_pane[pane_key(pane)]
end

local function get_git_info(pane)
	if is_herdr_pane(pane) then
		local focused = read_herdr_focused_git_info()
		if focused and focused.herdr_pane_id and focused.herdr_pane_id ~= "" then
			local from_shell = herdr_git_info_by_pane_id[focused.herdr_pane_id]
			if from_shell and from_shell.at >= focused.at then
				return from_shell.present and from_shell or nil
			end
		end
		return focused and focused.present and focused or nil
	end

	local info = get_git_info_from_user_vars(pane)
	return info and info.present and info or nil
end

local function render_right_status(window, pane)
	local segments = {}
	local active_key_table = window:active_key_table()
	local git_info = nil
	local ok, err = pcall(function()
		git_info = get_git_info(pane)
	end)

	if not ok then
		wezterm.log_error("right-status: " .. tostring(err))
	end

	local herdr_style = herdr_mode.styles[active_key_table]
	if herdr_style then
		table.insert(segments, { Background = { Color = herdr_style.bg } })
		table.insert(segments, { Foreground = { Color = herdr_style.fg } })
		table.insert(segments, { Attribute = { Intensity = "Bold" } })
		table.insert(segments, { Text = herdr_style.label })
		table.insert(segments, "ResetAttributes")
		table.insert(segments, { Background = { Color = STATUS_BG } })
	end

	if git_info then
		if #segments > 0 then
			table.insert(segments, { Foreground = { Color = "#565f89" } })
			table.insert(segments, { Text = "  " .. SEP .. "  " })
		end

		table.insert(segments, { Foreground = { Color = "#c0caf5" } })
		table.insert(segments, { Text = "  " .. git_info.repo })

		table.insert(segments, { Foreground = { Color = "#565f89" } })
		table.insert(segments, { Text = "  " .. SEP .. "  " })

		if git_info.flags:find("w") then
			table.insert(segments, { Foreground = { Color = "#9ece6a" } })
			table.insert(segments, { Text = "󰙅 " })
		end

		local is_detached = git_info.flags:find("D")
		table.insert(segments, { Foreground = { Color = is_detached and "#ff9e64" or "#7dcfff" } })
		table.insert(segments, { Text = " " .. git_info.ref })

		if git_info.flags:find("d") then
			table.insert(segments, { Foreground = { Color = "#e6c384" } })
			table.insert(segments, { Text = " *" })
		end

		for flag, badge in pairs(FLAG_BADGES) do
			if git_info.flags:find(flag) then
				table.insert(segments, { Foreground = { Color = badge.color } })
				table.insert(segments, { Text = badge.text })
			end
		end
	end

	-- Time
	table.insert(segments, { Foreground = { Color = "#565f89" } })
	table.insert(segments, { Text = "  " .. SEP .. "  " })
	table.insert(segments, { Foreground = { Color = "#bb9af7" } })
	table.insert(segments, { Text = " " .. wezterm.strftime("%a %b %e %H:%M") .. "  " })

	window:set_right_status(wezterm.format(segments))
end

wezterm.on("update-right-status", function(window, pane)
	render_right_status(window, pane)
end)

wezterm.on("render-right-status", function(window, pane)
	render_right_status(window, pane or window:active_pane())
end)

wezterm.on("user-var-changed", function(window, pane, name, value)
	if name ~= "WEZ_GIT_INFO" then
		return
	end

	local ok, err = pcall(function()
		accept_git_info_for_pane(pane, parse_git_payload(value))
		local active_pane = window:active_pane()
		if active_pane and pane_key(active_pane) == pane_key(pane) then
			render_right_status(window, active_pane)
		end
	end)

	if not ok then
		wezterm.log_error("right-status user-var: " .. tostring(err))
	end
end)

wezterm.on("window-focus-changed", function(window, pane)
	render_right_status(window, pane)
end)

wezterm.on("window-config-reloaded", function(window, pane)
	herdr_mode.clear_all_modes()
	pane = pane or window:active_pane()
	if pane then
		render_right_status(window, pane)
	end
end)
