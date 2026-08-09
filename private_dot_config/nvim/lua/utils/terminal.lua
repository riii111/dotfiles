local M = {}

local terminals = {}

local function window_config(fullscreen)
	local width = fullscreen and math.max(vim.o.columns - 4, 1) or math.max(math.floor(vim.o.columns * 0.9), 1)
	local height = fullscreen and math.max(vim.o.lines - 4, 1) or math.max(math.floor(vim.o.lines * 0.6), 1)

	return {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = width,
		height = height,
		col = math.max(math.floor((vim.o.columns - width) / 2), 0),
		row = math.max(math.floor((vim.o.lines - height) / 2), 0),
	}
end

local function hide(terminal)
	if terminal and vim.api.nvim_win_is_valid(terminal.win) then
		vim.api.nvim_win_close(terminal.win, true)
	end
end

local function set_keymaps(key, terminal)
	local opts = { buffer = terminal.buf, silent = true }
	vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], opts)
	for _, lhs in ipairs({ "<C-\\>", "<C-S-@>", "<C-S-2>", "<F12>" }) do
		vim.keymap.set("t", lhs, function()
			hide(terminals[key])
		end, opts)
	end
	vim.keymap.set("n", "<Esc>", function()
		hide(terminals[key])
	end, opts)
	vim.keymap.set("n", "q", function()
		hide(terminals[key])
	end, opts)
end

local function show(key, terminal)
	terminal.win = vim.api.nvim_open_win(terminal.buf, true, window_config(terminal.fullscreen))
	vim.cmd.startinsert()
	terminals[key] = terminal
end

function M.toggle(opts)
	opts = opts or {}
	local key = opts.key or "shell"
	local terminal = terminals[key]

	if terminal and vim.api.nvim_buf_is_valid(terminal.buf) then
		if vim.api.nvim_win_is_valid(terminal.win) then
			hide(terminal)
		else
			show(key, terminal)
		end
		return
	end

	terminal = {
		buf = vim.api.nvim_create_buf(false, true),
		fullscreen = opts.fullscreen == true,
	}
	vim.bo[terminal.buf].bufhidden = "hide"
	show(key, terminal)
	set_keymaps(key, terminal)

	local command = opts.command or vim.o.shell
	terminal.job = vim.fn.jobstart(command, {
		cwd = opts.cwd or vim.fn.getcwd(),
		term = true,
		on_exit = function()
			vim.schedule(function()
				if terminals[key] == terminal then
					terminals[key] = nil
				end
				if vim.api.nvim_buf_is_valid(terminal.buf) then
					vim.api.nvim_buf_delete(terminal.buf, { force = true })
				end
			end)
		end,
	})

	if terminal.job <= 0 then
		terminals[key] = nil
		vim.api.nvim_buf_delete(terminal.buf, { force = true })
		vim.notify("Failed to start terminal", vim.log.levels.ERROR)
	end
end

return M
