local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- モジュール読み込み
local keymaps = require("keymaps")
require("on")
require("zen-mode")

---------------------------------------------------------------
-- Font
---------------------------------------------------------------
config.font = wezterm.font("DroidSansM Nerd Font Mono")
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
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.show_new_tab_button_in_tab_bar = false

---------------------------------------------------------------
-- Pane
---------------------------------------------------------------
config.inactive_pane_hsb = {
	saturation = 0.95,
	brightness = 0.85,
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
local kanagawa_dragon = require("colors.kanagawa_dragon")
config.colors = kanagawa_dragon.colors

---------------------------------------------------------------
-- Misc
---------------------------------------------------------------
config.audible_bell = "Disabled"
config.enable_csi_u_key_encoding = true

return config
