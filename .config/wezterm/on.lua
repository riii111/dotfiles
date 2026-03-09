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
				"-c",
				"let g:scrollback_cursor_x = " .. cursor.x,
				"-c",
				"let g:scrollback_marker = '" .. marker .. "'",
				"-c",
				"let g:scrollback_prev_tab = " .. tab_id,
				"-c",
				"luafile " .. pager,
				-- tail keeps process alive to suppress "[Process exited 0]"
				"-c",
				"terminal cat " .. tmp .. "; rm " .. tmp .. "; touch '" .. marker .. "'; tail -f /dev/null",
			},
		}),
		pane
	)
end)

-- Toggle window opacity (dark <-> light frosted-glass)
wezterm.on("toggle-opacity", function(window, _)
	local overrides = window:get_config_overrides() or {}
	if not overrides.window_background_opacity then
		-- Light mode: brighter, more wallpaper visible
		overrides.window_background_opacity = 0.85
		overrides.macos_window_background_blur = 20
		overrides.background = {
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
				opacity = 0.21,
			},
		}
	else
		-- Dark mode: restore defaults
		overrides.window_background_opacity = nil
		overrides.macos_window_background_blur = nil
		overrides.background = nil
	end
	window:set_config_overrides(overrides)
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
	return " " .. name .. " "
end)

-- Right status: repo, git ref, flags, time
-- Parsed from zsh precmd title: "repo::ref::flags"
-- Flags: d=dirty, D=detached, w=worktree, R=rebase, M=merge, C=cherry-pick
local SEP = "\u{e0b3}"

local FLAG_BADGES = {
	R = { text = " REBASE", color = "#ff9e64" },
	M = { text = " MERGE", color = "#ff9e64" },
	C = { text = " PICK", color = "#ff9e64" },
}

wezterm.on("update-status", function(window, pane)
	local title = pane:get_title()

	local segments = {}

	-- Only show git info when title matches our "repo::ref" format
	if title:find("::") then
		local parts = {}
		for part in title:gmatch("[^:]+") do
			table.insert(parts, part)
		end
		local dir = parts[1] or title
		local ref = parts[2]
		local flags = parts[3] or ""

		table.insert(segments, { Foreground = { Color = "#c0caf5" } })
		table.insert(segments, { Text = "  " .. dir })

		if ref and #ref > 0 then
			table.insert(segments, { Foreground = { Color = "#565f89" } })
			table.insert(segments, { Text = "  " .. SEP .. "  " })

			-- Worktree badge
			if flags:find("w") then
				table.insert(segments, { Foreground = { Color = "#9ece6a" } })
				table.insert(segments, { Text = "󰙅 " })
			end

			local is_detached = flags:find("D")
			table.insert(segments, { Foreground = { Color = is_detached and "#ff9e64" or "#7dcfff" } })
			table.insert(segments, { Text = " " .. ref })

			-- Dirty indicator
			if flags:find("d") then
				table.insert(segments, { Foreground = { Color = "#e6c384" } })
				table.insert(segments, { Text = " *" })
			end

			-- Rebase / Merge / Cherry-pick badge
			for flag, badge in pairs(FLAG_BADGES) do
				if flags:find(flag) then
					table.insert(segments, { Foreground = { Color = badge.color } })
					table.insert(segments, { Text = badge.text })
				end
			end
		end
	end

	-- Time
	table.insert(segments, { Foreground = { Color = "#565f89" } })
	table.insert(segments, { Text = "  " .. SEP .. "  " })
	table.insert(segments, { Foreground = { Color = "#bb9af7" } })
	table.insert(segments, { Text = " " .. wezterm.strftime("%a %b %e %H:%M") .. "  " })

	window:set_right_status(wezterm.format(segments))
end)
