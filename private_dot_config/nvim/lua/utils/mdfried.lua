local M = {}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "mdfried" })
end

local function executable(name)
	local path = vim.fn.exepath(name)
	if path == "" then
		notify(name .. " is not available in PATH", vim.log.levels.ERROR)
		return nil
	end
	return path
end

function M.open()
	if vim.bo.filetype ~= "markdown" then
		notify("mdfried is available for Markdown buffers only", vim.log.levels.WARN)
		return
	end

	if not vim.env.KITTY_LISTEN_ON or vim.env.KITTY_LISTEN_ON == "" then
		notify("Kitty remote control is not available; restart Kitty and Neovim", vim.log.levels.ERROR)
		return
	end

	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		notify("save the Markdown buffer before opening mdfried", vim.log.levels.WARN)
		return
	end

	if not pcall(vim.cmd, "update") then
		notify("could not save the Markdown buffer", vim.log.levels.ERROR)
		return
	end

	local kitten = executable("kitten")
	local mdfried = executable("mdfried")
	if not kitten or not mdfried then
		return
	end

	vim.system(
		{
			kitten,
			"@",
			"launch",
			"--self",
			"--no-response",
			"--type=overlay",
			"--cwd=" .. vim.fs.dirname(path),
			mdfried,
			path,
		},
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				notify(
					vim.trim(result.stderr) ~= "" and vim.trim(result.stderr) or "failed to launch mdfried",
					vim.log.levels.ERROR
				)
			end
		end)
	)
end

return M
