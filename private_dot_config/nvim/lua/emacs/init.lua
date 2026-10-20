-- Emacs editing mode: Insert mode entered with `e` in Normal mode, with Emacs keys mapped to its buffer
-- until Insert mode ends. Plain Insert mode and other buffers are left alone.
local motion = require("emacs.motion")
local edit = require("emacs.edit")
local region = require("emacs.region")

local M = {}

local DESC = "Emacs mode"
local group = vim.api.nvim_create_augroup("emacs_mode", { clear = false })
local namespace = vim.api.nvim_create_namespace("emacs_mode")

local keys = {
	["<C-f>"] = "forward_char",
	["<C-b>"] = "backward_char",
	["<C-n>"] = "next_line",
	["<C-p>"] = "previous_line",
	["<C-a>"] = "line_start",
	["<C-e>"] = "line_end",
	["<M-f>"] = "forward_word",
	["<M-b>"] = "backward_word",
	["<M-lt>"] = "buffer_start",
	["<M->>"] = "buffer_end",
	["<C-d>"] = "delete_char",
	["<Del>"] = "delete_char",
	["<BS>"] = "delete_backward_char",
	["<C-h>"] = "delete_backward_char",
	["<C-u>"] = "kill_line_start",
	["<C-k>"] = "kill_line_end",
	["<M-d>"] = "kill_word",
	["<M-BS>"] = "backward_kill_word",
	["<C-y>"] = "yank",
	["<M-y>"] = "yank_pop",
	["<C-v>"] = "scroll_down",
	["<M-v>"] = "scroll_up",
	["<C-l>"] = "recenter",
	["<M-r>"] = "move_to_window_line",
	["<M-{>"] = "backward_paragraph",
	["<M-}>"] = "forward_paragraph",
	["<C-w>"] = "kill_region",
	["<M-w>"] = "copy_region",
	["<C-g>"] = "keyboard_quit",
	["<M-h>"] = "mark_paragraph",
	-- terminals send CTRL-/ as CTRL-_
	["<C-/>"] = "undo",
	["<C-_>"] = "undo",
}

-- C-SPC reaches Neovim as <C-@> from terminals that send it as NUL; macOS may take it for the input source
local DEFAULT_SET_MARK = { "<C-Space>", "<C-@>" }
local set_mark_keys = DEFAULT_SET_MARK

-- pending: `e` was pressed and Insert mode is about to start; active: the mode is on in this buffer and window
local state = { pending = nil, active = nil }
-- counts the keys typed while the mode is on; a kill continues the previous one only when no other key came between
local key_sequence = 0
local last_kill
-- the column C-n and C-p aim at, kept while they move the cursor one after another
local vertical_goal
-- where C-y or M-y put the text last; M-y replaces it when it comes right after them
local last_yank
-- the step C-l or M-r took last; pressed again right after, they go on to the next step
local last_cycle

local function cursor()
	local pos = vim.api.nvim_win_get_cursor(0)
	return { pos[1] - 1, pos[2] }
end

-- defined below, in the order the mode goes through them
local editable, on_mode_changed, activate, restore, commands, close_completion

-- opts.set_mark: the keys that set the mark, replacing C-SPC and C-@
function M.setup(opts)
	M.teardown()
	set_mark_keys = opts and opts.set_mark or DEFAULT_SET_MARK
	vim.keymap.set("n", "e", function()
		return editable(0) and "<Cmd>lua require('emacs').start()<CR>" or "e"
	end, { expr = true, desc = DESC })
	vim.api.nvim_create_autocmd("ModeChanged", { group = group, callback = on_mode_changed })
	vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, {
		group = group,
		callback = function()
			if state.active then
				M.stop()
			end
		end,
	})
	-- typed text and other changes end the region; moves of other keys, such as the arrow keys, stretch it
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = group,
		callback = function(args)
			if state.active and region.changed(args.buf) then
				region.clear()
			end
		end,
	})
	vim.api.nvim_create_autocmd("CursorMovedI", {
		group = group,
		callback = function(args)
			if state.active then
				region.draw(args.buf, cursor())
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = group,
		callback = function(args)
			if state.active and state.active.buf == args.buf then
				M.stop()
			end
		end,
	})
	vim.on_key(function(_, typed)
		if state.active and typed ~= "" then
			key_sequence = key_sequence + 1
		end
	end, namespace)
end

-- Enters Insert mode at the cursor like `i`; the keys are mapped once Insert mode has started, after the
-- InsertEnter autocommands that map keys of their own (blink.cmp does).
function M.start()
	local buf = vim.api.nvim_get_current_buf()
	if state.active or not editable(buf) then
		return false
	end
	state.pending = { buf = buf, win = vim.api.nvim_get_current_win() }
	vim.cmd.startinsert()
	return true
end

function M.is_active()
	return state.active ~= nil
end

function M.run(name)
	local active = state.active
	if not (active and active.buf == vim.api.nvim_get_current_buf()) then
		return
	end
	local command = commands[name]
	if command.kind ~= "kill" then
		last_kill = nil
	end
	if command.kind ~= "vertical" then
		vertical_goal = nil
	end
	command.run(active.buf, cursor())
	-- moves stretch the region; anything else ends it
	if command.keeps_region then
		region.draw(active.buf, cursor())
	else
		region.clear()
	end
end

function M.close_completion()
	close_completion()
end

function M.stop()
	state.pending = nil
	local active = state.active
	if not active then
		return
	end
	state.active = nil
	last_kill = nil
	vertical_goal = nil
	last_yank = nil
	last_cycle = nil
	region.clear()
	restore(active)
	vim.cmd.redrawstatus()
end

function M.teardown()
	M.stop()
	vim.api.nvim_clear_autocmds({ group = group })
	vim.on_key(nil, namespace)
	if vim.fn.maparg("e", "n", false, true).desc == DESC then
		vim.keymap.del("n", "e")
	end
end

-- Entering and leaving

function editable(buf)
	return vim.bo[buf].buftype == "" and vim.bo[buf].modifiable
end

local function in_normal_mode(mode)
	return mode == "n" or mode == "nt" or vim.startswith(mode, "t")
end

function on_mode_changed()
	local new = vim.v.event.new_mode
	local pending = state.pending
	if pending then
		state.pending = nil
		if
			new == "i"
			and pending.buf == vim.api.nvim_get_current_buf()
			and pending.win == vim.api.nvim_get_current_win()
		then
			activate(pending.buf, pending.win)
		end
		return
	end
	if not (state.active and in_normal_mode(new)) then
		return
	end
	local old = vim.v.event.old_mode
	if vim.startswith(old, "i") or vim.startswith(old, "R") then
		M.stop()
	else
		-- i_CTRL-O passes through niI and the modes of its command, also Normal mode for :normal, and then comes
		-- back to Insert mode; only :stopinsert and the like stay in Normal mode
		local active = state.active
		vim.schedule(function()
			if state.active == active and in_normal_mode(vim.api.nvim_get_mode().mode) then
				M.stop()
			end
		end)
	end
end

-- <C-g>u on both sides makes every command its own undo step without joining the text typed around it
local function rhs(name)
	return ("<Cmd>lua require('emacs').close_completion()<CR><C-g>u<Cmd>lua require('emacs').run(%q)<CR><C-g>u"):format(
		name
	)
end

local function install(buf)
	local saved = {}
	vim.api.nvim_buf_call(buf, function()
		local function map(lhs, name)
			local mapping = vim.fn.maparg(lhs, "i", false, true)
			saved[lhs] = mapping.buffer == 1 and mapping or false
			vim.keymap.set("i", lhs, rhs(name), { buffer = buf, nowait = true, silent = true, desc = DESC })
		end
		for lhs, name in pairs(keys) do
			map(lhs, name)
		end
		for _, lhs in ipairs(set_mark_keys) do
			map(lhs, "set_mark")
		end
	end)
	return saved
end

-- A block cursor like Normal mode and Emacs, set in 'guicursor' after what is there so the rest stays
local function block_cursor()
	local guicursor = vim.o.guicursor
	if guicursor == "" then
		return nil
	end
	local block = guicursor .. ",i-ci:block"
	vim.o.guicursor = block
	return { saved = guicursor, set = block }
end

function activate(buf, win)
	state.active = { buf = buf, win = win, saved = install(buf), cursor = block_cursor() }
	vim.cmd.redrawstatus()
end

local function ours(mapping)
	return mapping.buffer == 1 and mapping.desc == DESC
end

-- Puts back the cursor and what was mapped before, unless something changed them in the meantime.
function restore(active)
	local cursor_shape = active.cursor
	if cursor_shape and vim.o.guicursor == cursor_shape.set then
		vim.o.guicursor = cursor_shape.saved
	end
	local buf = active.buf
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_call(buf, function()
		for lhs, mapping in pairs(active.saved) do
			if ours(vim.fn.maparg(lhs, "i", false, true)) then
				vim.api.nvim_buf_del_keymap(buf, "i", lhs)
				if mapping then
					vim.fn.mapset("i", false, mapping)
				end
			end
		end
	end)
end

-- Commands

function close_completion()
	if package.loaded["blink.cmp"] then
		-- blink.cmp's own cancel() is deferred and would undo the preview after this command has edited the text
		pcall(function()
			if require("blink.cmp").is_visible() then
				require("blink.cmp.completion.list").undo_preview()
				require("blink.cmp.completion.trigger").hide()
			end
		end)
	end
	if vim.fn.pumvisible() == 1 then
		vim.api.nvim_feedkeys(vim.keycode("<C-e>"), "ni", false)
	end
end

local function moving(target)
	return {
		keeps_region = true,
		run = function(buf, pos)
			local to = target(buf, pos)
			if to then
				edit.set_cursor(to)
			end
		end,
	}
end

local function deleting(from, to)
	return {
		run = function(buf, pos)
			local first, last = from(buf, pos), to(buf, pos)
			if first and last then
				edit.delete(first, last)
			end
		end,
	}
end

local function here(_, pos)
	return pos
end

-- kills the text between the cursor and target; a kill in a row adds backward kills in front
local function killing(target)
	return {
		kind = "kill",
		run = function(buf, pos)
			local to = target(buf, pos)
			local backward = to and (to[1] < pos[1] or (to[1] == pos[1] and to[2] < pos[2]))
			local continued = last_kill
				and last_kill.buf == buf
				and last_kill.tick == vim.b.changedtick
				and vim.deep_equal(last_kill.pos, pos)
				and last_kill.key_sequence == key_sequence - 1
			if to then
				edit.store(edit.delete(pos, to), continued and (backward and "prepend" or "append") or "replace")
			elseif not continued then
				last_kill = nil
				return
			end
			last_kill = { buf = buf, tick = vim.b.changedtick, pos = cursor(), key_sequence = key_sequence }
		end,
	}
end

-- Runs a Normal mode command from Insert mode and returns 'curswant'. Normal mode commands cannot put the cursor
-- after the last character without 'virtualedit'. Setting it recomputes 'curswant', so prepare() runs after it
-- is set and 'curswant' is read before it is restored.
local function normal(keys, prepare)
	local win = vim.api.nvim_get_current_win()
	local virtualedit = vim.api.nvim_get_option_value("virtualedit", { scope = "local", win = win })
	local function set_virtualedit(value)
		vim.api.nvim_cmd({ cmd = "setlocal", args = { "virtualedit=" .. value }, mods = { noautocmd = true } }, {})
	end
	set_virtualedit("onemore")
	if prepare then
		prepare()
	end
	-- without autocommands, Normal mode here is not taken for the end of Insert mode
	local ok, err = pcall(vim.api.nvim_cmd, {
		cmd = "normal",
		args = { vim.keycode(keys) },
		bang = true,
		mods = { noautocmd = true },
	}, {})
	local curswant = vim.fn.winsaveview().curswant
	set_virtualedit(virtualedit)
	assert(ok, err)
	return curswant
end

-- gj and gk keep the target column in 'curswant', which Insert mode resets after every command
local function screen_line(direction)
	return {
		kind = "vertical",
		keeps_region = true,
		run = function(_, pos)
			local win = vim.api.nvim_get_current_win()
			local curswant = normal("g" .. direction, function()
				local goal = vertical_goal
				if goal and goal.win == win and goal.tick == vim.b.changedtick and vim.deep_equal(goal.pos, pos) then
					vim.fn.winrestview({ curswant = goal.curswant })
				end
			end)
			vertical_goal = { win = win, tick = vim.b.changedtick, pos = cursor(), curswant = curswant }
		end,
	}
end

local function normal_command(keys)
	return {
		keeps_region = true,
		run = function()
			normal(keys)
		end,
	}
end

-- Like Emacs' recenter-positions: the middle of the window first, then the top and the bottom.
local function cycling(steps)
	local command = { keeps_region = true }
	function command.run()
		local cycle = last_cycle
		local step = 1
		if cycle and cycle.command == command and cycle.key_sequence == key_sequence - 1 then
			step = cycle.step % #steps + 1
		end
		normal(steps[step])
		last_cycle = { command = command, step = step, key_sequence = key_sequence }
	end
	return command
end

commands = {
	forward_char = moving(motion.forward_char),
	backward_char = moving(motion.backward_char),
	next_line = screen_line("j"),
	previous_line = screen_line("k"),
	line_start = moving(motion.line_start),
	line_end = moving(motion.line_end),
	forward_word = moving(motion.forward_word),
	backward_word = moving(motion.backward_word),
	buffer_start = moving(motion.buffer_start),
	buffer_end = moving(motion.buffer_end),
	delete_char = deleting(here, motion.forward_char),
	delete_backward_char = deleting(motion.backward_char, here),
	kill_line_start = killing(motion.line_start),
	kill_line_end = killing(motion.kill_line_end),
	kill_word = killing(motion.forward_word),
	backward_kill_word = killing(motion.backward_word),
	yank = {
		run = function(buf, pos)
			local text = edit.to_yank()
			if text then
				local to = edit.insert(pos, text)
				last_yank = { buf = buf, from = pos, to = to, tick = vim.b.changedtick, key_sequence = key_sequence }
			end
		end,
	},
	-- does nothing unless it comes right after C-y or M-y, as Emacs refuses to
	yank_pop = {
		run = function(buf, pos)
			local yank = last_yank
			if
				not yank
				or yank.buf ~= buf
				or yank.tick ~= vim.b.changedtick
				or not vim.deep_equal(yank.to, pos)
				or yank.key_sequence ~= key_sequence - 1
			then
				return
			end
			local text = edit.rotate()
			edit.delete(yank.from, yank.to)
			local to = edit.insert(yank.from, text)
			last_yank = { buf = buf, from = yank.from, to = to, tick = vim.b.changedtick, key_sequence = key_sequence }
		end,
	},
	scroll_down = normal_command("<C-f>"),
	scroll_up = normal_command("<C-b>"),
	recenter = cycling({ "zz", "zt", "zb" }),
	-- Emacs puts the cursor at the start of the line
	move_to_window_line = cycling({ "M0", "H0", "L0" }),
	backward_paragraph = moving(motion.backward_paragraph),
	forward_paragraph = moving(motion.forward_paragraph),
	set_mark = {
		keeps_region = true,
		run = function(buf, pos)
			region.set_mark(buf, pos)
		end,
	},
	-- without a region, C-w kills the word before the cursor as in Readline and Vim
	kill_region = killing(function(buf, pos)
		local mark = region.mark(buf)
		if mark then
			return not vim.deep_equal(mark, pos) and mark or nil
		end
		return motion.backward_word(buf, pos)
	end),
	copy_region = {
		run = function(buf, pos)
			local mark = region.mark(buf)
			if mark and not vim.deep_equal(mark, pos) then
				edit.store(edit.text(mark, pos), "replace")
			end
		end,
	},
	-- ends the region and nothing else
	keyboard_quit = { run = function() end },
	-- the region from the separating line before the paragraph to the one after it, as Emacs marks it
	mark_paragraph = {
		keeps_region = true,
		run = function(buf, pos)
			local to = motion.forward_paragraph(buf, pos) or pos
			region.set_mark(buf, to)
			edit.set_cursor(motion.backward_paragraph(buf, to) or to)
		end,
	},
	undo = {
		run = function()
			vim.cmd("silent! undo")
		end,
	},
}

return M
