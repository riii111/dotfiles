local function healthy()
	for _, plugin in pairs(require("lazy.core.config").plugins) do
		for _, task in ipairs(plugin._.tasks or {}) do
			assert(not task:has_errors(), plugin.name .. ": " .. task:output())
		end
	end
	assert(#nvim_test_errors == 0, table.concat(nvim_test_errors, "\n"))
	assert(vim.v.errmsg == "", vim.v.errmsg)
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
	healthy()
end

vim.schedule(function()
	local ok, err = xpcall(function()
		healthy()
		if vim.env.DOTFILES_NVIM_MODE == "update" then
			require("lazy").update({ wait = true, show = false })
			healthy()
		else
			smoke()
			dofile(vim.env.DOTFILES_NVIM_CONSTRAINTS_SCRIPT)
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
