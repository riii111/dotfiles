local function healthy()
	for _, plugin in pairs(require("lazy.core.config").plugins) do
		for _, task in ipairs(plugin._.tasks or {}) do
			assert(not task:has_errors(), plugin.name .. ": " .. task:output())
		end
	end
	assert(#nvim_test_errors == 0, table.concat(nvim_test_errors, "\n"))
	assert(vim.v.errmsg == "", vim.v.errmsg)
end

-- lazy.nvim merges only these fields across the specs of one plugin. Any other field comes from the
-- last spec that sets it, so the same field in an earlier spec is silently dead code.
local merged = { "opts", "opts_extend", "dependencies", "specs", "cmd", "event", "ft", "keys" }

-- lazy.nvim chains the specs of a resolved plugin through metatables, the last spec first.
local function specs_of(plugin)
	local specs = {}
	local meta = getmetatable(plugin)
	while meta and type(meta.__index) == "table" do
		table.insert(specs, 1, meta.__index)
		meta = getmetatable(meta.__index)
	end
	return specs
end

local function origin(value)
	if type(value) ~= "function" then
		return vim.inspect(value)
	end
	local info = debug.getinfo(value, "S")
	local path = info.source:sub(2):gsub("^.*/lua/", "")
	return path .. ":" .. info.linedefined
end

local function unshadowed()
	local chained = 0
	local found = {}
	for name, plugin in pairs(require("lazy.core.config").plugins) do
		local specs = specs_of(plugin)
		chained = chained + (#specs > 1 and 1 or 0)

		local origins = {}
		for _, spec in ipairs(specs) do
			-- Specs shipped by a plugin are marked optional: defaults that the config is meant to override.
			for field, value in pairs(rawget(spec, "optional") and {} or spec) do
				if field ~= 1 and not vim.tbl_contains(merged, field) then
					origins[field] = origins[field] or {}
					table.insert(origins[field], origin(value))
				end
			end
		end
		for field, where in pairs(origins) do
			if #where > 1 then
				local message = "%s: `%s` is set by %d specs (%s)"
				table.insert(found, message:format(name, field, #where, table.concat(where, ", ")))
			end
		end
	end
	assert(chained > 0, "lazy.nvim no longer chains the specs of a plugin through metatables; update this check")
	table.sort(found)
	assert(
		#found == 0,
		"A field set by several specs of one plugin runs only from the last spec. Move each setup into its own\n"
			.. "`virtual = true` spec (see private_dot_config/nvim/AGENTS.md):\n"
			.. table.concat(found, "\n")
	)
end

local function has_source(null_ls, filetype, method)
	for _, source in ipairs(null_ls.get_sources()) do
		if source.filetypes[filetype] and source.methods[null_ls.methods[method]] then
			return true
		end
	end
	return false
end

-- Language setups live in their own specs; each one must have run once its trigger fired.
local function languages()
	assert(vim.env.GOROOT and vim.env.GOPATH, "go-env-setup did not run")
	assert(vim.lsp.is_enabled("nixd"), "nix-lsp-setup did not run")

	local null_ls = require("null-ls")
	assert(has_source(null_ls, "nix", "FORMATTING"), "nixfmt is not registered")

	vim.cmd.enew()
	vim.bo.filetype = "python"
	assert(vim.lsp.is_enabled("basedpyright"), "python-lsp-setup did not run")
	assert(has_source(null_ls, "python", "FORMATTING"), "ruff formatting is not registered")
	assert(has_source(null_ls, "python", "DIAGNOSTICS"), "ruff diagnostics are not registered")

	vim.cmd.enew()
	vim.bo.filetype = "terraform"
	assert(vim.lsp.is_enabled("terraform_ls"), "terraform-lsp-setup did not run")
	assert(has_source(null_ls, "terraform", "FORMATTING"), "terraform fmt is not registered")
	assert(has_source(null_ls, "terraform", "DIAGNOSTICS"), "tflint is not registered")
	for _, lhs in ipairs({ "<M-CR>", "<D-S-r>", "<M-S-r>" }) do
		assert(vim.fn.maparg(lhs, "n", false, true).buffer == 1, "terraform keymap " .. lhs .. " is not set")
	end
end

local function smoke()
	local fixture = vim.env.DOTFILES_NVIM_FIXTURE
	vim.cmd.edit(vim.fn.fnameescape(fixture .. "/sample.lua"))
	assert(
		vim.wait(30000, function()
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0, name = "lua_ls" })) do
				if client.initialized then
					return true
				end
			end
		end),
		"Lua language server did not attach"
	)
	local replies = vim.lsp.buf_request_sync(0, "textDocument/hover", {
		textDocument = { uri = vim.uri_from_bufnr(0) },
		position = { line = 0, character = 24 },
	}, 10000)
	assert(replies and vim.iter(vim.tbl_values(replies)):any(function(reply)
		return reply.result and reply.result.contents
	end), "Lua hover returned no content")

	local capabilities = require("blink.cmp").get_lsp_capabilities()
	assert(capabilities.textDocument.completion.completionItem.snippetSupport, "Completion setup failed")
	require("nvim-treesitter").install({ "lua" }):wait(120000)
	local parser = vim.treesitter.get_parser(0, "lua")
	assert(parser:parse()[1], "Lua parser failed")

	require("telescope.builtin").find_files({ cwd = fixture })
	local prompt = vim.api.nvim_get_current_buf()
	local picker = require("telescope.actions.state").get_current_picker(prompt)
	assert(
		vim.wait(10000, function()
			return picker.manager and picker.manager:num_results() > 0
		end),
		"Telescope found no files"
	)
	require("telescope.actions").close(prompt)

	require("oil").open(fixture)
	assert(
		vim.wait(10000, function()
			return vim.bo.filetype == "oil" and #require("oil").get_current_dir() > 0
		end),
		"Oil did not open the directory"
	)
	languages()
	healthy()
end

vim.schedule(function()
	local ok, err = xpcall(function()
		healthy()
		if vim.env.DOTFILES_NVIM_MODE == "update" then
			require("lazy").update({ wait = true, show = false })
			healthy()
		else
			unshadowed()
			smoke()
		end
	end, debug.traceback)
	if not ok then
		io.stderr:write(err .. "\n")
		vim.cmd("cquit 1")
	else
		print("Neovim " .. vim.env.DOTFILES_NVIM_MODE .. ": OK")
		vim.cmd("qa!")
	end
end)
