local recorded_actions = {}
local recorded_panes = {}
local scheduled_callbacks = {}

local function action(name)
	return function(value)
		return { name = name, value = value }
	end
end

local wezterm = {
	action = {
		ActivateKeyTable = action("ActivateKeyTable"),
		EmitEvent = action("EmitEvent"),
		Multiple = action("Multiple"),
		PopKeyTable = { name = "PopKeyTable" },
		SendKey = action("SendKey"),
		SendString = action("SendString"),
	},
	action_callback = function(callback)
		return { name = "Callback", callback = callback }
	end,
	time = {
		call_after = function(_, callback)
			table.insert(scheduled_callbacks, callback)
		end,
	},
	GLOBAL = {},
}

package.preload.wezterm = function()
	return wezterm
end

local source = debug.getinfo(1, "S").source:gsub("^@", "")
local test_dir = source:match("^(.*[/\\])") or "./"
package.path = test_dir .. "../?.lua;" .. package.path

local herdr_mode = require("herdr_mode")
local PREFIX = "\x1b[59;5u"
local MODE = {
	main = "herdr_mode",
	copy = "herdr_copy_mode",
	selection = "herdr_selection_mode",
}

local keys = {}
local key_tables = {}
herdr_mode.install(keys, key_tables)

local pane_process = "/opt/homebrew/bin/herdr"
local tmux_active = false
local active_pane = {}
local active_pane_fails = false
local pane = {
	get_foreground_process_name = function()
		return pane_process
	end,
	get_user_vars = function()
		return { TMUX_ACTIVE = tmux_active and "1" or nil }
	end,
}

local window = {
	window_id = function()
		return 42
	end,
	perform_action = function(_, wezterm_action, target_pane)
		table.insert(recorded_actions, wezterm_action)
		table.insert(recorded_panes, target_pane)
	end,
	active_pane = function()
		if active_pane_fails then
			error("pane closed")
		end
		return active_pane
	end,
}

local function reset_recording()
	recorded_actions = {}
	recorded_panes = {}
	scheduled_callbacks = {}
end

local function find_binding(table_name, key, mods)
	for _, binding in ipairs(key_tables[table_name]) do
		if binding.key == key and binding.mods == mods then
			return binding
		end
	end
	return nil
end

local function run_binding(table_name, key, mods)
	reset_recording()
	local binding = assert(find_binding(table_name, key, mods), "binding not found: " .. key)
	assert(binding.action.name == "Callback", "expected callback: " .. key)
	binding.action.callback(window, pane)
	return recorded_actions
end

local prefix_binding = keys[#keys]
local function enable_mode()
	reset_recording()
	pane_process = "/opt/homebrew/bin/herdr"
	tmux_active = false
	prefix_binding.action.callback(window, pane)
	assert(herdr_mode.active_mode_for_tab({ window_id = 42 }) == MODE.main)
end

local function assert_send(multiple, expected)
	assert(multiple.name == "Multiple")
	assert(multiple.value[1].name == "SendString")
	assert(multiple.value[1].value == PREFIX)
	assert(multiple.value[2].name == expected.name)
	if expected.name == "SendKey" then
		assert(multiple.value[2].value.key == expected.key)
		assert(multiple.value[2].value.mods == expected.mods)
	else
		assert(multiple.value[2].value == expected.value)
	end
end

local handoff_cases = {
	{ "p", "ALT", { name = "SendKey", key = "p", mods = "ALT" } },
	{ "t", nil, { name = "SendKey", key = "t", mods = "NONE" } },
	{ "t", "ALT", { name = "SendKey", key = "t", mods = "ALT" } },
	{ "V", "SHIFT", { name = "SendString", value = "\x1b[118;2u" } },
	{ "P", "SHIFT", { name = "SendString", value = "\x1b[112;2u" } },
	{ "T", "SHIFT", { name = "SendString", value = "\x1b[116;2u" } },
	{ "w", "ALT", { name = "SendKey", key = "w", mods = "ALT" } },
	{ "W", "SHIFT", { name = "SendString", value = "\x1b[119;2u" } },
	{ "g", "CTRL", { name = "SendKey", key = "g", mods = "CTRL" } },
	{ "?", nil, { name = "SendKey", key = "?", mods = "NONE" } },
	{ "s", nil, { name = "SendKey", key = "s", mods = "NONE" } },
	{ "s", "CTRL", { name = "SendKey", key = "s", mods = "CTRL" } },
	{ "O", "SHIFT", { name = "SendString", value = "\x1b[111;2u" } },
}

for _, case in ipairs(handoff_cases) do
	enable_mode()
	local actions = run_binding(MODE.main, case[1], case[2])
	assert_send(actions[1], case[3])
	assert(actions[2].name == "PopKeyTable")
	assert(herdr_mode.active_mode_for_tab({ window_id = 42 }) == nil)
end

for _, case in ipairs({
	{ "h", { name = "SendKey", key = "h", mods = "NONE" } },
	{ "p", { name = "SendKey", key = "p", mods = "NONE" } },
	{ "w", { name = "SendKey", key = "w", mods = "NONE" } },
	{ "z", { name = "SendKey", key = "z", mods = "NONE" } },
}) do
	assert_send(assert(find_binding(MODE.main, case[1], nil)).action, case[2])
end

enable_mode()
run_binding(MODE.main, "v", nil)
local copy_complete = run_binding(MODE.copy, "y", nil)
assert(copy_complete[1].value.key == "y" and copy_complete[1].value.mods == "NONE")
assert(copy_complete[2].name == "PopKeyTable")

enable_mode()
run_binding(MODE.main, "v", nil)
local copy_cancel = run_binding(MODE.copy, "q", nil)
assert(copy_cancel[1].value.key == "q" and copy_cancel[1].value.mods == "NONE")
assert(copy_cancel[2].value.name == MODE.main)

enable_mode()
run_binding(MODE.main, "Space", nil)
local selection_complete = run_binding(MODE.selection, "Enter", nil)
assert(selection_complete[1].value.key == "Enter")
assert(selection_complete[2].name == "PopKeyTable")

enable_mode()
local toggle_off = run_binding(MODE.main, ";", "CTRL")
assert(toggle_off[1].name == "PopKeyTable")

herdr_mode.clear_all_modes()
reset_recording()
tmux_active = true
prefix_binding.action.callback(window, pane)
assert(recorded_actions[1].name == "SendString" and recorded_actions[1].value == PREFIX)

reset_recording()
tmux_active = false
pane_process = "/bin/zsh"
prefix_binding.action.callback(window, pane)
assert(recorded_actions[1].value.name == "leader")

enable_mode()
local replacement_pane = {}
active_pane = replacement_pane
scheduled_callbacks[1]()
assert(recorded_panes[#recorded_panes] == replacement_pane)

active_pane_fails = true
assert(pcall(scheduled_callbacks[1]))

print("herdr_mode_test: ok")
