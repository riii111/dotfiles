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

local function focused_kitty_socket(kitten)
	if vim.env.HERDR_ENV ~= "1" then
		return nil
	end

	for name, kind in vim.fs.dir("/tmp") do
		if kind == "socket" and name:match("^kitty%-%d+$") then
			local address = "unix:/tmp/" .. name
			local result = vim.system({ kitten, "@", "--to", address, "ls" }, { text = true }):wait()
			if result.code == 0 then
				local ok, os_windows = pcall(vim.json.decode, result.stdout)
				if ok then
					for _, os_window in ipairs(os_windows) do
						if os_window.is_focused then
							return address
						end
					end
				end
			end
		end
	end

	return nil
end

function M.open()
	if vim.bo.filetype ~= "markdown" then
		notify("mdfried is available for Markdown buffers only", vim.log.levels.WARN)
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

	local in_herdr = vim.env.HERDR_ENV == "1"
	local kitty_socket = in_herdr and nil or vim.env.KITTY_LISTEN_ON
	if in_herdr then
		kitty_socket = focused_kitty_socket(kitten)
	end
	if not kitty_socket or kitty_socket == "" then
		notify("no focused Kitty window with remote control is available", vim.log.levels.ERROR)
		return
	end

	local command = { kitten, "@", "--to", kitty_socket, "launch" }
	if not in_herdr then
		table.insert(command, "--self")
	end
	vim.list_extend(command, {
		"--no-response",
		"--type=overlay",
		"--cwd=" .. vim.fs.dirname(path),
		mdfried,
		path,
	})

	vim.system(
		command,
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
