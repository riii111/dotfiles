-- The hooks of plugins/emacs-mode.lua with the real neoscroll.nvim and blink.cmp. They are configured as in the
-- config when this runs.
local check = {}
_G.emacs_mode_check = check

local function feed(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "tx", false)
end

local function scrolling()
	local state = package.loaded["neoscroll.scroll"]
	return state ~= nil and state.scrolling
end

local function maps()
	local found = {}
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, "i")) do
		if mapping.desc == "Emacs mode" then
			table.insert(found, mapping.lhs)
		end
	end
	return found
end

function check.settle()
	assert(
		vim.wait(3000, function()
			return not scrolling()
		end, 5),
		"neoscroll did not stop"
	)
end

function check.snap(label)
	check[label] = {
		active = require("emacs-mode").is_active(),
		top = vim.fn.line("w0"),
		row = vim.fn.line("."),
		guicursor = vim.o.guicursor,
		maps = #maps(),
		lines = vim.api.nvim_buf_get_lines(0, 0, -1, true),
		col = vim.fn.col("."),
		menu = package.loaded["blink.cmp"] and package.loaded["blink.cmp"].is_menu_visible(),
	}
end

local function eq(expected, actual, what)
	assert(
		vim.deep_equal(expected, actual),
		("%s\nexpected: %s\n  actual: %s"):format(what, vim.inspect(expected), vim.inspect(actual))
	)
end

local function window(lines)
	vim.cmd.new()
	vim.cmd.resize(10)
	vim.wo.scrolloff = 0
	vim.api.nvim_buf_set_lines(0, 0, -1, true, lines)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function smooth_scrolling()
	local lines = {}
	for i = 1, 100 do
		lines[i] = "line " .. i
	end
	local termguicolors, guicursor = vim.o.termguicolors, vim.o.guicursor
	vim.o.termguicolors = true
	window(lines)

	feed("e<C-v><Cmd>lua emacs_mode_check.settle()<CR><Cmd>lua emacs_mode_check.snap('down')<CR><Esc>")
	eq(
		{ true, 11, 11, true },
		{ check.down.active, check.down.top, check.down.row, check.down.maps > 0 },
		"C-v animated"
	)
	assert(check.down.guicursor:find(",i-ci:block", 1, true), "no block cursor in the mode: " .. check.down.guicursor)
	eq({ false, guicursor, {} }, { require("emacs-mode").is_active(), vim.o.guicursor, maps() }, "after Esc")

	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.fn.winrestview({ topline = 1 })
	feed("e<C-v><Esc>")
	local animating
	assert(
		vim.wait(3000, function()
			animating = scrolling()
			return not require("emacs-mode").is_active()
		end, 1),
		"the mode stays on after Esc during the animation"
	)
	assert(animating, "the animation was over before the mode ended; the case checked nothing")
	check.settle()
	eq({ guicursor, {} }, { vim.o.guicursor, maps() }, "after Esc during the animation")

	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	vim.fn.winrestview({ topline = 1 })
	local buf = vim.api.nvim_get_current_buf()
	feed("e<C-v><C-o>:enew<CR>")
	check.settle()
	feed("<Esc>")
	eq(
		{ false, guicursor },
		{ require("emacs-mode").is_active(), vim.o.guicursor },
		"after leaving the buffer during the animation"
	)
	vim.api.nvim_buf_delete(buf, { force = true })

	vim.o.termguicolors = termguicolors
	vim.cmd("bwipeout!")
end

local function completion()
	local cmp = require("blink.cmp")
	function check.show()
		cmp.show()
		assert(vim.wait(5000, cmp.is_menu_visible, 5), "blink.cmp shows no menu")
	end
	function check.previewed()
		assert(
			vim.wait(2000, function()
				return vim.fn.getline(2) ~= "al"
			end, 5),
			"selecting an item did not preview it"
		)
	end
	local show = "<Cmd>lua emacs_mode_check.show()<CR>"
	local previewed = "<Cmd>lua emacs_mode_check.previewed()<CR>"
	local function snap(label)
		return ("<Cmd>lua emacs_mode_check.snap(%q)<CR>"):format(label)
	end
	local original = { "alpha alphabet", "al", "next" }
	local function session(keys)
		window(original)
		feed("e<Cmd>lua vim.api.nvim_win_set_cursor(0, { 2, 2 })<CR>" .. keys .. "<Esc>")
		vim.cmd("bwipeout!")
	end

	session(show .. "<Down>" .. previewed .. snap("preview") .. "<C-a>" .. snap("moved"))
	assert(check.preview.lines[2] ~= "al", "no preview in " .. vim.inspect(check.preview.lines))
	eq(
		{ original, 2, 1, false },
		{ check.moved.lines, check.moved.row, check.moved.col, check.moved.menu },
		"C-a with a previewed item"
	)

	session(show .. "<Down>" .. previewed .. "<C-k>" .. snap("killed") .. "<C-_>" .. snap("undone"))
	eq({ "alpha alphabet", "alnext" }, check.killed.lines, "C-k with a previewed item")
	eq(original, check.undone.lines, "undo after C-k with a previewed item")

	session(show .. "<C-n>" .. snap("next"))
	eq({ original, 3, false }, { check.next.lines, check.next.row, check.next.menu }, "C-n on a menu")

	session(show .. "<Down>" .. previewed .. "<C-n>" .. snap("next"))
	eq({ original, 3 }, { check.next.lines, check.next.row }, "C-n with a previewed item")
end

return function()
	smooth_scrolling()
	completion()
end
