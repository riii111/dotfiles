local wezterm = require("wezterm")
local act = wezterm.action
local io = require("io")
local os = require("os")

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

	-- marker file signals cat completion without polluting the terminal buffer
	local marker = os.tmpname() .. "_done"
	local cursor = pane:get_cursor_position()
	local tab_id = window:active_tab():tab_id()
	local pager = wezterm.config_dir .. "/scrollback-pager.lua"
	window:perform_action(
		act.SpawnCommandInNewTab({
			args = {
				"/opt/homebrew/bin/nvim",
				"-c", "let g:scrollback_cursor_x = " .. cursor.x,
				"-c", "let g:scrollback_marker = '" .. marker .. "'",
				"-c", "let g:scrollback_prev_tab = " .. tab_id,
				"-c", "luafile " .. pager,
				-- tail keeps process alive to suppress "[Process exited 0]"
				"-c", "terminal cat " .. tmp .. "; rm " .. tmp
					.. "; touch '" .. marker .. "'; tail -f /dev/null",
			},
		}),
		pane
	)
end)

-- Toggle window opacity
wezterm.on("toggle-opacity", function(window, _)
	local overrides = window:get_config_overrides() or {}
	if not overrides.window_background_opacity then
		overrides.window_background_opacity = 0.6
	else
		overrides.window_background_opacity = nil
	end
	window:set_config_overrides(overrides)
end)

-- Toggle background blur
wezterm.on("toggle-blur", function(window, _)
	local overrides = window:get_config_overrides() or {}
	if not overrides.macos_window_background_blur then
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
	return " " .. name .. " "
end)

-- Right status: dir, git branch, time (parsed from zsh precmd "dir::branch")
local SEP = "\u{e0b3}"

wezterm.on("update-status", function(window, pane)
	local title = pane:get_title()
	local dir, branch = title:match("^(.+)::(.+)$")
	if not dir then
		dir = title
	end

	local segments = {}

	-- Directory
	table.insert(segments, { Foreground = { Color = "#c0caf5" } })
	table.insert(segments, { Text = "  " .. dir })

	-- Git branch
	if branch and #branch > 0 then
		table.insert(segments, { Foreground = { Color = "#565f89" } })
		table.insert(segments, { Text = "  " .. SEP .. "  " })
		table.insert(segments, { Foreground = { Color = "#7dcfff" } })
		table.insert(segments, { Text = " " .. branch })
	end

	-- Time
	table.insert(segments, { Foreground = { Color = "#565f89" } })
	table.insert(segments, { Text = "  " .. SEP .. "  " })
	table.insert(segments, { Foreground = { Color = "#bb9af7" } })
	table.insert(segments, { Text = " " .. wezterm.strftime("%H:%M") .. "  " })

	window:set_right_status(wezterm.format(segments))
end)
