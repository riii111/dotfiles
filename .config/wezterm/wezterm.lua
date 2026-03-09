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
config.window_background_opacity = 0.35
config.macos_window_background_blur = 40
config.window_decorations = "RESIZE"
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
-- Background: layered frosted-glass effect
---------------------------------------------------------------
config.background = {
	-- Base layer: warm dark gradient aligned with Kanagawa Dragon
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
	-- Accent layer: warm purple wash for depth
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
config.macos_forward_to_ime_modifier_mask = "SHIFT|CTRL"

---------------------------------------------------------------
-- Leader key (for tab switching etc.)
---------------------------------------------------------------
config.leader = { key = ";", mods = "CTRL", timeout_milliseconds = 2000 }

---------------------------------------------------------------
-- Key bindings
---------------------------------------------------------------
config.keys = keymaps

---------------------------------------------------------------
-- Color scheme
---------------------------------------------------------------
-- Register custom Kanagawa Dragon (with adjusted bright black)
local kanagawa_dragon = require("colors.kanagawa_dragon")
config.color_schemes = {
	["Kanagawa Dragon"] = kanagawa_dragon.colors,
}
config.color_scheme = "Kanagawa Dragon"

---------------------------------------------------------------
-- Misc
---------------------------------------------------------------
config.max_fps = 165
config.audible_bell = "Disabled"
config.enable_csi_u_key_encoding = true
config.adjust_window_size_when_changing_font_size = false
config.hide_mouse_cursor_when_typing = true

return config
