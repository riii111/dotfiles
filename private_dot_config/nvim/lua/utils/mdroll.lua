local M = {}

local state = {
	pane_id = nil,
	path = nil,
	busy = false,
}

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "mdroll" })
end

local function run(args, callback)
	vim.system(args, { text = true }, callback)
end

local function pane_exists(pane_id, callback)
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

local function launch(path)
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
			notify(vim.trim(result.stderr) ~= "" and vim.trim(result.stderr) or "failed to split a WezTerm pane", vim.log.levels.ERROR)
			return
		end

		local pane_id = tonumber(vim.trim(result.stdout))
		if not pane_id then
			notify("WezTerm did not return a pane id", vim.log.levels.ERROR)
			return
		end

		state.pane_id = pane_id
		state.path = path
	end)
end

local function close_then_launch(path)
	local pane_id = state.pane_id
	state.pane_id = nil
	state.path = nil

	run({ "wezterm", "cli", "kill-pane", "--pane-id", tostring(pane_id) }, function(result)
		if result.code ~= 0 then
			notify(vim.trim(result.stderr) ~= "" and vim.trim(result.stderr) or "failed to close the previous mdroll pane", vim.log.levels.ERROR)
			return
		end
		launch(path)
	end)
end

function M.open()
	if vim.bo.filetype ~= "markdown" then
		notify("mdroll is available for Markdown buffers only", vim.log.levels.WARN)
		return
	end

	if vim.env.WEZTERM_PANE == nil or vim.env.WEZTERM_PANE == "" then
		notify("WEZTERM_PANE is not set; open Neovim directly in WezTerm", vim.log.levels.ERROR)
		return
	end

	if vim.fn.executable("mdroll") == 0 then
		notify("mdroll is not installed; run dotctl sync-nix-profile", vim.log.levels.ERROR)
		return
	end

	if vim.fn.executable("wezterm") == 0 then
		notify("wezterm is not available in PATH", vim.log.levels.ERROR)
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
		launch(path)
		return
	end

	pane_exists(state.pane_id, function(exists)
		if exists == nil then
			notify("could not inspect WezTerm panes", vim.log.levels.ERROR)
			return
		end

		if not exists then
			state.pane_id = nil
			state.path = nil
			launch(path)
			return
		end

		if state.path == path then
			notify("mdroll is already open for this buffer")
			return
		end

		close_then_launch(path)
	end)
end

return M
