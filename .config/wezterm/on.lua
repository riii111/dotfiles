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
	local pager = wezterm.config_dir .. "/scrollback-pager.lua"
	window:perform_action(
		act.SpawnCommandInNewTab({
			args = {
				"/opt/homebrew/bin/nvim",
				"-c", "let g:scrollback_cursor_x = " .. cursor.x,
				"-c", "let g:scrollback_marker = '" .. marker .. "'",
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
