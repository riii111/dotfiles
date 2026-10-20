-- Emacs editing mode: Insert mode entered with `e` in Normal mode, with Emacs keys mapped to its buffer
-- until Insert mode ends. Plain Insert mode and other buffers are left alone.
local motion = require("emacs.motion")
local edit = require("emacs.edit")

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
	-- terminals send CTRL-/ as CTRL-_
	["<C-/>"] = "undo",
	["<C-_>"] = "undo",
}

-- pending: `e` was pressed and Insert mode is about to start; active: the mode is on in this buffer and window
local state = { pending = nil, active = nil }
-- keys typed while the mode is on; a kill continues the previous one only when no other key came between them
local typed = 0
local last_kill
-- the column C-n and C-p aim at, kept while they move the cursor one after another
local goal

local function cursor()
	local pos = vim.api.nvim_win_get_cursor(0)
	return { pos[1] - 1, pos[2] }
end

local function editable(buf)
	return vim.bo[buf].buftype == "" and vim.bo[buf].modifiable
end

local function close_completion()
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

local function move(target)
	if target then
		edit.set_cursor(target)
	end
end

local function remove(from, to)
	if from and to then
		edit.delete(from, to)
	end
end

local function kill(from, to, backward)
	local buf = vim.api.nvim_get_current_buf()
	local pos = cursor()
	local continued = last_kill
		and last_kill.buf == buf
		and last_kill.tick == vim.b.changedtick
		and vim.deep_equal(last_kill.pos, pos)
		and last_kill.typed == typed - 1
	if from and to then
		edit.store(edit.delete(from, to), continued and (backward and "prepend" or "append") or "replace")
	elseif not continued then
		last_kill = nil
		return
	end
	last_kill = { buf = buf, tick = vim.b.changedtick, pos = cursor(), typed = typed }
end

-- gj and gk keep the target column in 'curswant', which Insert mode resets after every command
local function screen_line(direction)
	local win = vim.api.nvim_get_current_win()
	local pos = cursor()
	-- Normal mode commands cannot put the cursor after the last character without 'virtualedit'. Setting it
	-- recomputes 'curswant', so the column is put back after it is set and read before it is restored.
	local virtualedit = vim.api.nvim_get_option_value("virtualedit", { scope = "local", win = win })
	local function set_virtualedit(value)
		vim.api.nvim_cmd({ cmd = "setlocal", args = { "virtualedit=" .. value }, mods = { noautocmd = true } }, {})
	end
	set_virtualedit("onemore")
	if goal and goal.win == win and goal.tick == vim.b.changedtick and vim.deep_equal(goal.pos, pos) then
		vim.fn.winrestview({ curswant = goal.curswant })
	end
	local ok, err = pcall(vim.api.nvim_cmd, {
		cmd = "normal",
		args = { "g" .. direction },
		bang = true,
		mods = { noautocmd = true },
	}, {})
	local curswant = vim.fn.winsaveview().curswant
	set_virtualedit(virtualedit)
	assert(ok, err)
	goal = { win = win, tick = vim.b.changedtick, pos = cursor(), curswant = curswant }
end

local commands = {
	forward_char = function(buf, pos)
		move(motion.forward_char(buf, pos))
	end,
	backward_char = function(buf, pos)
		move(motion.backward_char(buf, pos))
	end,
	next_line = function()
		screen_line("j")
	end,
	previous_line = function()
		screen_line("k")
	end,
	line_start = function(buf, pos)
		move(motion.line_start(buf, pos))
	end,
	line_end = function(buf, pos)
		move(motion.line_end(buf, pos))
	end,
	forward_word = function(buf, pos)
		move(motion.forward_word(buf, pos))
	end,
	backward_word = function(buf, pos)
		move(motion.backward_word(buf, pos))
	end,
	buffer_start = function(buf, pos)
		move(motion.buffer_start(buf, pos))
	end,
	buffer_end = function(buf, pos)
		move(motion.buffer_end(buf, pos))
	end,
	delete_char = function(buf, pos)
		remove(pos, motion.forward_char(buf, pos))
	end,
	delete_backward_char = function(buf, pos)
		remove(motion.backward_char(buf, pos), pos)
	end,
	kill_line_start = function(buf, pos)
		kill(motion.line_start(buf, pos), pos, true)
	end,
	kill_line_end = function(buf, pos)
		local to = motion.kill_line_end(buf, pos)
		kill(to and pos, to, false)
	end,
	kill_word = function(buf, pos)
		local to = motion.forward_word(buf, pos)
		kill(to and pos, to, false)
	end,
	backward_kill_word = function(buf, pos)
		kill(motion.backward_word(buf, pos), pos, true)
	end,
	yank = function(_, pos)
		local text = edit.killed()
		if text then
			edit.insert(pos, text)
		end
	end,
	undo = function()
		vim.cmd("silent! undo")
	end,
}

local kills = { kill_line_start = true, kill_line_end = true, kill_word = true, backward_kill_word = true }
local vertical = { next_line = true, previous_line = true }

function M.run(name)
	local active = state.active
	if not (active and active.buf == vim.api.nvim_get_current_buf()) then
		return
	end
	if not kills[name] then
		last_kill = nil
	end
	if not vertical[name] then
		goal = nil
	end
	commands[name](active.buf, cursor())
end

-- <C-g>u on both sides makes every command its own undo step without joining the text typed around it
local function rhs(name)
	return ("<Cmd>lua require('emacs').close_completion()<CR><C-g>u<Cmd>lua require('emacs').run(%q)<CR><C-g>u"):format(
		name
	)
end

M.close_completion = close_completion

local function ours(mapping)
	return mapping.buffer == 1 and mapping.desc == DESC
end

local function install(buf)
	local saved = {}
	vim.api.nvim_buf_call(buf, function()
		for lhs, name in pairs(keys) do
			local mapping = vim.fn.maparg(lhs, "i", false, true)
			saved[lhs] = mapping.buffer == 1 and mapping or false
			vim.keymap.set("i", lhs, rhs(name), { buffer = buf, nowait = true, silent = true, desc = DESC })
		end
	end)
	return saved
end

-- Puts back what was mapped before, unless something replaced the mode's mapping in the meantime.
local function restore(buf, saved)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_call(buf, function()
		for lhs, mapping in pairs(saved) do
			if ours(vim.fn.maparg(lhs, "i", false, true)) then
				vim.api.nvim_buf_del_keymap(buf, "i", lhs)
				if mapping then
					vim.fn.mapset("i", false, mapping)
				end
			end
		end
	end)
end

local function activate(buf, win)
	state.active = { buf = buf, win = win, saved = install(buf) }
	vim.cmd.redrawstatus()
end

function M.stop()
	state.pending = nil
	local active = state.active
	if not active then
		return
	end
	state.active = nil
	last_kill = nil
	goal = nil
	restore(active.buf, active.saved)
	vim.cmd.redrawstatus()
end

function M.is_active()
	return state.active ~= nil
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

local function on_mode_changed()
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
	if not (state.active and (new == "n" or new == "nt" or vim.startswith(new, "t"))) then
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
			local mode = vim.api.nvim_get_mode().mode
			if state.active == active and (mode == "n" or mode == "nt" or vim.startswith(mode, "t")) then
				M.stop()
			end
		end)
	end
end

function M.teardown()
	M.stop()
	vim.api.nvim_clear_autocmds({ group = group })
	vim.on_key(nil, namespace)
	if vim.fn.maparg("e", "n", false, true).desc == DESC then
		vim.keymap.del("n", "e")
	end
end

function M.setup()
	M.teardown()
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
	vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
		group = group,
		callback = function(args)
			if state.active and state.active.buf == args.buf then
				M.stop()
			end
		end,
	})
	vim.on_key(function(_, key)
		if state.active and key ~= "" then
			typed = typed + 1
		end
	end, namespace)
end

return M
