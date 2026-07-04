local wezterm = require("wezterm")
local config = wezterm.config_builder()

local keymaps = require("keymaps")
require("on")
require("zen-mode")

---------------------------------------------------------------
-- Font
---------------------------------------------------------------
-- Fallback prevents CJK punctuation from rendering at vertical center (HK/TW font style)
config.font = wezterm.font_with_fallback({
	"DroidSansM Nerd Font Mono",
	"Hiragino Sans",
})
config.font_size = 14.0

---------------------------------------------------------------
-- Window
---------------------------------------------------------------
config.window_background_opacity = 0.7
config.macos_window_background_blur = 20
config.window_decorations = "RESIZE|MACOS_FORCE_ENABLE_SHADOW"
config.window_padding = {
	left = 20,
	right = 20,
	top = 5,
	bottom = 5,
}

---------------------------------------------------------------
-- Tab bar
---------------------------------------------------------------
local TAB_BG = "#1f1f28"

config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = false
config.show_new_tab_button_in_tab_bar = false
config.window_frame = {
	font = wezterm.font("DroidSansM Nerd Font Mono", { weight = "Bold" }),
	font_size = 12.0,
	active_titlebar_bg = TAB_BG,
	inactive_titlebar_bg = TAB_BG,
}
config.colors = {
	tab_bar = {
		background = TAB_BG,
		active_tab = {
			bg_color = "#2a2a37",
			fg_color = "#c5c9c5",
			intensity = "Bold",
		},
		inactive_tab = {
			bg_color = TAB_BG,
			fg_color = "#565f89",
		},
		inactive_tab_hover = {
			bg_color = "#2a2a37",
			fg_color = "#c5c9c5",
		},
	},
}

---------------------------------------------------------------
-- Background: layered frosted-glass effect (Kanagawa Dragon only)
---------------------------------------------------------------
local KANAGAWA_BACKGROUND = {
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

---------------------------------------------------------------
-- Pane
---------------------------------------------------------------
config.inactive_pane_hsb = {
	saturation = 0.80,
	brightness = 0.60,
}

---------------------------------------------------------------
-- IME / Input
---------------------------------------------------------------
config.use_ime = true
-- Keep CTRL with macOS so Mission Control space switching is not sent to the pane.
config.macos_forward_to_ime_modifier_mask = "SHIFT"

---------------------------------------------------------------
-- Ctrl+Q: tmux-aware prefix / leader
-- In tmux  → pass through as tmux prefix
-- Outside → activate WezTerm leader key table
---------------------------------------------------------------
local act = wezterm.action

local function is_tmux(pane)
	local user_vars = pane:get_user_vars() or {}
	return user_vars.TMUX_ACTIVE == "1"
end

table.insert(keymaps, {
	key = "q",
	mods = "CTRL",
	action = wezterm.action_callback(function(window, pane)
		if is_tmux(pane) then
			window:perform_action(act.SendKey({ key = "q", mods = "CTRL" }), pane)
		else
			window:perform_action(
				act.ActivateKeyTable({ name = "leader", one_shot = true, timeout_milliseconds = 2000 }),
				pane
			)
		end
	end),
})

local HERDR_PREFIX = "\x1b[59;5u"

local function refresh_right_status(window, pane)
	window:perform_action(act.EmitEvent("render-right-status"), pane)
end

local function activate_herdr_table(name)
	return wezterm.action_callback(function(window, pane)
		window:perform_action(
			act.ActivateKeyTable({ name = name, one_shot = false, replace_current = true }),
			pane
		)
		refresh_right_status(window, pane)
	end)
end

local function pop_herdr_table()
	return wezterm.action_callback(function(window, pane)
		window:perform_action(act.PopKeyTable, pane)
		refresh_right_status(window, pane)
	end)
end

local function herdr_key(key, mods)
	return act.Multiple({
		act.SendString(HERDR_PREFIX),
		act.SendKey({ key = key, mods = mods or "NONE" }),
	})
end

local function herdr_shift_number(n)
	return act.Multiple({
		act.SendString(HERDR_PREFIX),
		act.SendString("\x1b[" .. string.byte(n) .. ";2u"),
	})
end

local function herdr_shift_key(key)
	return act.Multiple({
		act.SendString(HERDR_PREFIX),
		act.SendString("\x1b[" .. string.byte(key) .. ";2u"),
	})
end

local function herdr_key_table(key, table_name)
	return wezterm.action_callback(function(window, pane)
		window:perform_action(herdr_key(key), pane)
		window:perform_action(
			act.ActivateKeyTable({ name = table_name, one_shot = false, replace_current = true }),
			pane
		)
		refresh_right_status(window, pane)
	end)
end

local function herdr_resize_key(key)
	return wezterm.action_callback(function(window, pane)
		window:perform_action(herdr_key("r"), pane)
		window:perform_action(act.SendKey({ key = key, mods = "NONE" }), pane)
		window:perform_action(
			act.ActivateKeyTable({ name = "herdr_resize_mode", one_shot = false, replace_current = true }),
			pane
		)
		refresh_right_status(window, pane)
	end)
end

local function exit_herdr_resize_mode()
	return wezterm.action_callback(function(window, pane)
		window:perform_action(act.SendKey({ key = "Escape" }), pane)
		window:perform_action(act.PopKeyTable, pane)
		refresh_right_status(window, pane)
	end)
end

table.insert(keymaps, {
	key = ";",
	mods = "CTRL",
	action = activate_herdr_table("herdr_mode"),
})

---------------------------------------------------------------
-- Key bindings
---------------------------------------------------------------
config.keys = keymaps

---------------------------------------------------------------
-- Copy mode: add Y to yank current line (like Neovim)
---------------------------------------------------------------
local copy_mode = wezterm.gui.default_key_tables().copy_mode

-- Helper: yank with flash (copy, show selection briefly, then clear & close)
-- Uses get_selection_text_for_pane to strip trailing blank lines before copying,
-- which avoids the issue where vGy copies trailing empty lines from scrollback.
local function yank_with_flash(pre_actions)
	return wezterm.action_callback(function(window, pane)
		if pre_actions then
			for _, a in ipairs(pre_actions) do
				window:perform_action(a, pane)
			end
		end
		local text = window:get_selection_text_for_pane(pane)
		if text and text ~= "" then
			text = text:gsub("[\n \t]+$", "")
			window:copy_to_clipboard(text, "ClipboardAndPrimarySelection")
		else
			window:perform_action(act.CopyTo("ClipboardAndPrimarySelection"), pane)
		end
		wezterm.time.call_after(0.15, function()
			window:perform_action(act.CopyMode("ClearSelectionMode"), pane)
			window:perform_action(act.CopyMode("Close"), pane)
		end)
	end)
end

-- Remove default y binding, then re-add with flash
for i = #copy_mode, 1, -1 do
	if copy_mode[i].key == "y" and copy_mode[i].mods ~= "SHIFT" then
		table.remove(copy_mode, i)
	end
end
table.insert(copy_mode, {
	key = "y",
	mods = "NONE",
	action = yank_with_flash(),
})

-- Y: select cursor-to-EOL, then yank with flash
table.insert(copy_mode, {
	key = "y",
	mods = "SHIFT",
	action = yank_with_flash({
		act.CopyMode({ SetSelectionMode = "Cell" }),
		act.CopyMode("MoveToEndOfLineContent"),
	}),
})

config.key_tables = {
	copy_mode = copy_mode,
	herdr_mode = {
		{ key = "Escape", action = pop_herdr_table() },
		{ key = ";", mods = "CTRL", action = activate_herdr_table("herdr_mode") },

		{ key = "h", action = herdr_key("h") },
		{ key = "j", action = herdr_key("j") },
		{ key = "k", action = herdr_key("k") },
		{ key = "l", action = herdr_key("l") },

		{ key = "H", mods = "SHIFT", action = herdr_resize_key("h") },
		{ key = "J", mods = "SHIFT", action = herdr_resize_key("j") },
		{ key = "K", mods = "SHIFT", action = herdr_resize_key("k") },
		{ key = "L", mods = "SHIFT", action = herdr_resize_key("l") },

		{ key = "p", action = herdr_key("p") },
		{ key = "n", action = herdr_key("n") },
		{ key = "[", action = herdr_key("[") },
		{ key = "]", action = herdr_key("]") },
		{ key = ",", action = herdr_key(",") },
		{ key = ".", action = herdr_key(".") },

		{ key = "c", action = herdr_key("c") },
		{ key = "v", action = herdr_key("v") },
		{ key = "-", action = herdr_key("-") },
		{ key = "x", action = herdr_key("x") },
		{ key = "z", action = herdr_key("z") },

		{ key = "w", action = herdr_key("w") },
		{ key = "g", action = herdr_key("g") },
		{ key = "?", action = herdr_key("?") },
		{ key = "s", action = herdr_key("s") },
		{ key = "r", action = herdr_key_table("r", "herdr_resize_mode") },
		{ key = "R", mods = "SHIFT", action = herdr_shift_key("r") },
		{ key = "q", action = herdr_key("q") },
		{ key = "d", action = herdr_key("q") },

		{ key = "1", action = herdr_shift_number("1") },
		{ key = "2", action = herdr_shift_number("2") },
		{ key = "3", action = herdr_shift_number("3") },
		{ key = "4", action = herdr_shift_number("4") },
		{ key = "5", action = herdr_shift_number("5") },
		{ key = "6", action = herdr_shift_number("6") },
		{ key = "7", action = herdr_shift_number("7") },
		{ key = "8", action = herdr_shift_number("8") },
		{ key = "9", action = herdr_shift_number("9") },
	},
	herdr_resize_mode = {
		{ key = "Escape", action = exit_herdr_resize_mode() },
		{ key = "Enter", action = exit_herdr_resize_mode() },
		{ key = ";", mods = "CTRL", action = exit_herdr_resize_mode() },
		{ key = "r", action = exit_herdr_resize_mode() },

		{ key = "h", action = act.SendKey({ key = "h" }) },
		{ key = "j", action = act.SendKey({ key = "j" }) },
		{ key = "k", action = act.SendKey({ key = "k" }) },
		{ key = "l", action = act.SendKey({ key = "l" }) },
		{ key = "LeftArrow", action = act.SendKey({ key = "LeftArrow" }) },
		{ key = "DownArrow", action = act.SendKey({ key = "DownArrow" }) },
		{ key = "UpArrow", action = act.SendKey({ key = "UpArrow" }) },
		{ key = "RightArrow", action = act.SendKey({ key = "RightArrow" }) },
	},
	leader = {
		{ key = "f", action = act.Search("CurrentSelectionOrEmptyString") },
		{ key = "v", action = act.ActivateCopyMode },
		{ key = "V", mods = "SHIFT", action = act.EmitEvent("open-scrollback-in-nvim") },
		{ key = "Space", action = act.QuickSelect },
		{
			key = "t",
			action = act.InputSelector({
				title = "Color Scheme",
				choices = {
					{ label = "Kanagawa Dragon" },
					{ label = "Catppuccin Mocha" },
					{ label = "Catppuccin Macchiato" },
					{ label = "Catppuccin Frappe" },
					{ label = "Catppuccin Latte" },
					{ label = "duckbones" },
					{ label = "Black Metal (Bathory) (base16)" },
				},
				action = wezterm.action_callback(function(window, _, _, label)
					if label then
						local schemes = wezterm.get_builtin_color_schemes()
						schemes["Kanagawa Dragon"] = require("colors.kanagawa_dragon").colors
						local scheme = schemes[label]
						local bg = scheme and scheme.background or "#181616"
						local use_gradient = label == "Kanagawa Dragon"
						window:set_config_overrides({
							color_scheme = label,
							background = use_gradient and KANAGAWA_BACKGROUND or {},
							window_frame = {
								font = wezterm.font("DroidSansM Nerd Font Mono", { weight = "Bold" }),
								font_size = 12.0,
								active_titlebar_bg = bg,
								inactive_titlebar_bg = bg,
							},
						})
					end
				end),
			}),
		},
	},
}

---------------------------------------------------------------
-- Color scheme
---------------------------------------------------------------
-- Register custom Kanagawa Dragon (with adjusted bright black)
local kanagawa_dragon = require("colors.kanagawa_dragon")
config.color_schemes = {
	["Kanagawa Dragon"] = kanagawa_dragon.colors,
}
config.color_scheme = "Black Metal (Bathory) (base16)"

---------------------------------------------------------------
-- Misc
---------------------------------------------------------------
config.max_fps = 165
config.status_update_interval = 5000
config.audible_bell = "Disabled"
-- csi-u disabled: breaks Ctrl keys in tmux copy-mode
-- config.enable_csi_u_key_encoding = true
config.adjust_window_size_when_changing_font_size = false
config.hide_mouse_cursor_when_typing = true

return config
