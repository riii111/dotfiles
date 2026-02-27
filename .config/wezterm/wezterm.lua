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
config.window_background_opacity = 0.85
config.macos_window_background_blur = 20
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
config.tab_bar_at_bottom = false
config.use_fancy_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.show_new_tab_button_in_tab_bar = false
config.window_frame = {
	active_titlebar_bg = "#181616",
	inactive_titlebar_bg = "#181616",
}

---------------------------------------------------------------
-- Background
---------------------------------------------------------------
config.window_background_gradient = {
	colors = { "#181616" },
}

---------------------------------------------------------------
-- Pane
---------------------------------------------------------------
config.inactive_pane_hsb = {
	saturation = 0.95,
	brightness = 0.50,
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
