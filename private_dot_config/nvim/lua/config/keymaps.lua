-- Delete without yanking
vim.keymap.set({ "n", "v" }, "x", '"_x', { desc = "Delete character without yanking" })
vim.keymap.set({ "n", "v" }, "X", '"_d$', { desc = "Delete to end of line without yanking" })
vim.keymap.set({ "n", "v" }, "d", '"_d', { desc = "Delete without yanking" })
vim.keymap.set("n", "D", '"_D', { desc = "Delete to end of line without yanking" })
vim.keymap.set("n", "dd", '"_dd', { desc = "Delete line without yanking" })

-- Smart 0: toggle between ^ and 0
vim.keymap.set("n", "0", function()
	local line = vim.fn.getline(".")
	local col = vim.fn.col(".")
	local substring = line:sub(1, col - 1)
	return string.match(substring, "^%s+$") and "0" or "^"
end, { expr = true, silent = true, desc = "Smart 0: toggle ^ and 0" })

-- Smart i/A: auto-indent on empty lines
vim.keymap.set("n", "i", function()
	return vim.fn.len(vim.fn.getline(".")) ~= 0 and "i" or '"_cc'
end, { expr = true, silent = true, desc = "Smart i: auto-indent on empty lines" })

vim.keymap.set("n", "A", function()
	return vim.fn.len(vim.fn.getline(".")) ~= 0 and "A" or '"_cc'
end, { expr = true, silent = true, desc = "Smart A: auto-indent on empty lines" })

local function resize_window(direction)
	local amount = 3 * vim.v.count1
	local current_window = vim.fn.winnr()
	local at_right_edge = vim.fn.winnr("l") == current_window
	local at_bottom_edge = vim.fn.winnr("j") == current_window
	local delta

	if direction == "left" then
		delta = at_right_edge and amount or -amount
	elseif direction == "right" then
		delta = at_right_edge and -amount or amount
	elseif direction == "up" then
		delta = at_bottom_edge and amount or -amount
	else
		delta = at_bottom_edge and -amount or amount
	end

	local horizontal = direction == "left" or direction == "right"
	local command = horizontal and "vertical resize" or "resize"
	vim.cmd(("%s %s%d"):format(command, delta >= 0 and "+" or "", delta))
end

for key, direction in pairs({
	["<A-h>"] = "left",
	["<A-j>"] = "down",
	["<A-k>"] = "up",
	["<A-l>"] = "right",
}) do
	vim.keymap.set("n", key, function()
		resize_window(direction)
	end, { silent = true, desc = "Resize " .. direction })
end

-- Visual mode improvements
vim.keymap.set("x", "<", "<gv", { desc = "Indent left and keep selection" })
vim.keymap.set("x", ">", ">gv", { desc = "Indent right and keep selection" })
vim.keymap.set("x", "y", "mzy`z", { desc = "Yank and keep cursor position" })
