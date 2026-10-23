local duration = 100

local animations = {
	["<C-f>"] = function(neoscroll)
		neoscroll.ctrl_f({ duration = duration })
	end,
	["<C-b>"] = function(neoscroll)
		neoscroll.ctrl_b({ duration = duration })
	end,
	zz = function(neoscroll)
		neoscroll.zz({ half_win_duration = duration })
	end,
	zt = function(neoscroll)
		neoscroll.zt({ half_win_duration = duration })
	end,
	zb = function(neoscroll)
		neoscroll.zb({ half_win_duration = duration })
	end,
}

local scroll = {
	run = function(keys)
		local animate = animations[keys]
		local ok, neoscroll = pcall(require, "neoscroll")
		if not (animate and ok) then
			return false
		end
		animate(neoscroll)
		return true
	end,
	busy = function()
		local state = package.loaded["neoscroll.scroll"]
		return state ~= nil and state.scrolling
	end,
}

-- blink.cmp's cancel() undoes the preview of an item from a scheduled callback, which would run after the command
-- has edited the text. Waiting for its callback lets the preview go first.
local completion = {
	visible = function()
		local cmp = package.loaded["blink.cmp"]
		return cmp ~= nil and cmp.is_visible()
	end,
	close = function()
		local closed = false
		if package.loaded["blink.cmp"].cancel({
			callback = function()
				closed = true
			end,
		}) then
			vim.wait(500, function()
				return closed
			end, 1)
		end
	end,
}

local block

local function show_block_cursor()
	local guicursor = vim.o.guicursor
	if guicursor ~= "" then
		block = { saved = guicursor, set = guicursor .. ",i-ci:block" }
		vim.o.guicursor = block.set
	end
end

local function restore_cursor()
	local shape = block
	block = nil
	if not shape then
		return
	end
	local neoscroll = package.loaded["neoscroll.scroll"]
	if vim.o.guicursor == shape.set then
		vim.o.guicursor = shape.saved
	elseif neoscroll and neoscroll.scrolling and neoscroll.guicursor == shape.set then
		-- neoscroll hides the cursor while it scrolls and then puts back the guicursor it saved at the start.
		neoscroll.guicursor = shape.saved
	end
end

return {
	"riii111/emacs-mode.nvim",
	opts = { start_key = "e", scroll = scroll, completion = completion },
	config = function(_, opts)
		require("emacs-mode").setup(opts)
		local group = vim.api.nvim_create_augroup("emacs_mode_ui", { clear = true })
		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "EmacsModeEnter",
			callback = function()
				show_block_cursor()
				vim.cmd.redrawstatus()
			end,
		})
		vim.api.nvim_create_autocmd("User", {
			group = group,
			pattern = "EmacsModeLeave",
			callback = function()
				restore_cursor()
				vim.cmd.redrawstatus()
			end,
		})
	end,
}
