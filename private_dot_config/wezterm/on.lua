local wezterm = require("wezterm")
local act = wezterm.action
local io = require("io")
local os = require("os")

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
	return " " .. name .. " "
end)

-- Right status: repo, git ref, flags, time
local SEP = "\u{e0b3}"
local git_info_cache = {}
local git_info_cache_last_gc = 0

local FLAG_BADGES = {
	R = { text = " REBASE", color = "#ff9e64" },
	C = { text = " PICK", color = "#ff9e64" },
}

local function prune_git_info_cache(now)
	if now - git_info_cache_last_gc < 300 then
		return
	end

	for cwd, entry in pairs(git_info_cache) do
		if now - entry.at > 60 then
			git_info_cache[cwd] = nil
		end
	end

	git_info_cache_last_gc = now
end

local function cwd_to_path(cwd_uri)
	if not cwd_uri then
		return nil
	end

	if type(cwd_uri) == "table" or type(cwd_uri) == "userdata" then
		return cwd_uri.file_path or cwd_uri.path
	end

	local cwd = tostring(cwd_uri)
	if cwd:match("^file://") then
		cwd = cwd:gsub("^file://[^/]*", "")
		cwd = cwd:gsub("%%(%x%x)", function(hex)
			return string.char(tonumber(hex, 16))
		end)
	end
	return cwd
end

local function get_git_info(cwd)
	if not cwd or #cwd == 0 then
		return nil
	end

	local now = os.time()
	prune_git_info_cache(now)

	local cached = git_info_cache[cwd]
	if cached and now - cached.at < 5 then
		return cached.info
	end

	local success, stdout = wezterm.run_child_process({
		"/bin/sh",
		"-c",
		[[
cwd="$1"

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 1
git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null) || exit 1
common_dir=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null) || exit 1
ref=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null) && detached=0 || {
  ref=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null) || exit 1
  detached=1
}

# Dirty detection: avoid git status --porcelain (full working-tree scan)
# which can block WezTerm's synchronous run_child_process for seconds.
# git diff --quiet short-circuits on first diff and uses the stat cache.
dirty=0
git -C "$cwd" diff --quiet 2>/dev/null || dirty=1
[ "$dirty" = 0 ] && { git -C "$cwd" diff --quiet --cached 2>/dev/null || dirty=1; }
[ "$dirty" = 0 ] && [ -n "$(git -C "$cwd" ls-files --others --exclude-standard --directory --no-empty-directory 2>/dev/null | head -n 1)" ] && dirty=1

[ "${git_dir#/}" = "$git_dir" ] && git_dir="$root/$git_dir"
[ "${common_dir#/}" = "$common_dir" ] && common_dir="$root/$common_dir"

flags=""
[ "$detached" = 1 ] && flags="${flags}D"
[ "$dirty" = 1 ] && flags="${flags}d"
[ "$(realpath "$git_dir")" != "$(realpath "$common_dir")" ] && flags="${flags}w"
{ [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; } && flags="${flags}R"
[ -f "$git_dir/CHERRY_PICK_HEAD" ] && flags="${flags}C"

printf 'repo=%s\n' "${root##*/}"
printf 'ref=%s\n' "$ref"
printf 'flags=%s\n' "$flags"
]],
		"sh",
		cwd,
	})

	if not success then
		git_info_cache[cwd] = { at = now, info = nil }
		return nil
	end

	local info = { repo = nil, ref = nil, flags = "" }
	for line in stdout:gmatch("[^\r\n]+") do
		local key, value = line:match("^(%w+)=(.*)$")
		if key and value then
			info[key] = value
		end
	end

	if not info.repo or not info.ref then
		info = nil
	end

	git_info_cache[cwd] = { at = now, info = info }
	return info
end

local function render_right_status(window, pane)
	local segments = {}
	local active_key_table = window:active_key_table()
	local git_info = nil
	local ok, err = pcall(function()
		local cwd = cwd_to_path(pane:get_current_working_dir())
		git_info = get_git_info(cwd)
	end)

	if not ok then
		wezterm.log_error("right-status: " .. tostring(err))
	end

	if active_key_table == "herdr_mode" or active_key_table == "herdr_resize_mode" then
		table.insert(segments, { Foreground = { Color = "#9ece6a" } })
		table.insert(segments, { Text = active_key_table == "herdr_resize_mode" and " HERDR:RESIZE" or " HERDR" })
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

wezterm.on("window-focus-changed", function(window, pane)
	render_right_status(window, pane)
end)

wezterm.on("window-config-reloaded", function(window, pane)
	pane = pane or window:active_pane()
	if pane then
		render_right_status(window, pane)
	end
end)
