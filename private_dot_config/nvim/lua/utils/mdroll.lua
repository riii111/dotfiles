local M = {}

local state = {
	pane_id = nil,
	path = nil,
	busy = false,
	backend = nil,
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "mdroll" })
end

local function run(args, callback)
	vim.system(args, { text = true }, vim.schedule_wrap(callback))
end

local function current_backend()
	return vim.env.HERDR_PANE_ID and vim.env.HERDR_PANE_ID ~= "" and "herdr" or "wezterm"
end

local function pane_exists(pane_id, backend, callback)
	if backend == "herdr" then
		run({ "herdr", "pane", "get", pane_id }, function(result)
			if result.code == 0 then
				callback(true)
				return
			end

			local ok, response = pcall(vim.json.decode, result.stdout)
			if ok and response.error and response.error.code == "pane_not_found" then
				callback(false)
				return
			end

			callback(nil)
		end)
		return
	end

	run({ "wezterm", "cli", "list", "--format", "json" }, function(result)
		if result.code ~= 0 then
			callback(nil)
			return
		end

		local ok, panes = pcall(vim.json.decode, result.stdout)
		if not ok or type(panes) ~= "table" then
			callback(nil)
			return
		end

		for _, pane in ipairs(panes) do
			if tonumber(pane.pane_id) == pane_id then
				callback(true)
				return
			end
		end

		callback(false)
	end)
end

local function launch_in_herdr(path)
	local directory = vim.fs.dirname(path)
	state.busy = true
	run({
		"herdr",
		"pane",
		"split",
		"--current",
		"--direction",
		"right",
		"--ratio",
		"0.45",
		"--cwd",
		directory,
		"--no-focus",
	}, function(result)
		if result.code ~= 0 then
			state.busy = false
			notify(
				vim.trim(result.stderr) ~= "" and vim.trim(result.stderr) or "failed to split a Herdr pane",
				vim.log.levels.ERROR
			)
			return
		end

		local ok, response = pcall(vim.json.decode, result.stdout)
		local pane_id = ok and response.result and response.result.pane and response.result.pane.pane_id or nil
		if type(pane_id) ~= "string" then
			state.busy = false
			notify("Herdr did not return a pane id", vim.log.levels.ERROR)
			return
		end

		local command = table.concat({
			"exec mdroll --watch --no-remote-images --mermaid text",
			vim.fn.shellescape(path),
		}, " ")
		run({ "herdr", "pane", "run", pane_id, command }, function(run_result)
			state.busy = false
			if run_result.code ~= 0 then
				notify(
					vim.trim(run_result.stderr) ~= "" and vim.trim(run_result.stderr)
						or "failed to start mdroll in Herdr",
					vim.log.levels.ERROR
				)
				return
			end

			state.pane_id = pane_id
			state.path = path
			state.backend = "herdr"
		end)
	end)
end

local function launch_in_wezterm(path)
	local directory = vim.fs.dirname(path)
	state.busy = true
	run({
		"wezterm",
		"cli",
		"split-pane",
		"--right",
		"--percent",
		"45",
		"--cwd",
		directory,
		"--",
		"mdroll",
		"--watch",
		"--no-remote-images",
		"--mermaid",
		"text",
		path,
	}, function(result)
		state.busy = false
		if result.code ~= 0 then
			notify(
				vim.trim(result.stderr) ~= "" and vim.trim(result.stderr) or "failed to split a WezTerm pane",
				vim.log.levels.ERROR
			)
			return
		end

		local pane_id = tonumber(vim.trim(result.stdout))
		if not pane_id then
			notify("WezTerm did not return a pane id", vim.log.levels.ERROR)
			return
		end

		state.pane_id = pane_id
		state.path = path
		state.backend = "wezterm"
	end)
end

local function launch(path, backend)
	if backend == "herdr" then
		launch_in_herdr(path)
	else
		launch_in_wezterm(path)
	end
end

local function close_then_launch(path, backend)
	local pane_id = state.pane_id
	local previous_backend = state.backend
	state.pane_id = nil
	state.path = nil
	state.backend = nil

	local close_args = previous_backend == "herdr" and { "herdr", "pane", "close", pane_id }
		or { "wezterm", "cli", "kill-pane", "--pane-id", tostring(pane_id) }
	run(close_args, function(result)
		if result.code ~= 0 then
			notify(
				vim.trim(result.stderr) ~= "" and vim.trim(result.stderr) or "failed to close the previous mdroll pane",
				vim.log.levels.ERROR
			)
			return
		end
		launch(path, backend)
	end)
end

function M.open()
	if vim.bo.filetype ~= "markdown" then
		notify("mdroll is available for Markdown buffers only", vim.log.levels.WARN)
		return
	end

	local backend = current_backend()
	if backend == "wezterm" and (vim.env.WEZTERM_PANE == nil or vim.env.WEZTERM_PANE == "") then
		notify("WEZTERM_PANE is not set; open Neovim directly in WezTerm", vim.log.levels.ERROR)
		return
	end

	if vim.fn.executable("mdroll") == 0 then
		notify("mdroll is not installed; run dotctl sync-nix-profile", vim.log.levels.ERROR)
		return
	end

	if vim.fn.executable(backend) == 0 then
		notify(backend .. " is not available in PATH", vim.log.levels.ERROR)
		return
	end

	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		notify("save the Markdown buffer before opening mdroll", vim.log.levels.WARN)
		return
	end

	if not pcall(vim.cmd, "update") then
		notify("could not save the Markdown buffer", vim.log.levels.ERROR)
		return
	end

	if state.busy then
		return
	end

	if not state.pane_id then
		launch(path, backend)
		return
	end

	pane_exists(state.pane_id, state.backend, function(exists)
		if exists == nil then
			notify("could not inspect the mdroll pane", vim.log.levels.ERROR)
			return
		end

		if not exists then
			state.pane_id = nil
			state.path = nil
			state.backend = nil
			launch(path, backend)
			return
		end

		if state.path == path then
			notify("mdroll is already open for this buffer")
			return
		end

		close_then_launch(path, backend)
	end)
end

return M
