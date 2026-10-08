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

-- Stub tools at the front of PATH let the revived none-ls sources run the way format-on-save and
-- diagnostics do. A source that is registered but broken (no on_output, wrong stream, exit status,
-- arguments or directory, shifted columns) then has no effect or a wrong one.
local function tool(path, script)
	vim.fn.writefile(vim.split("#!/bin/sh\n" .. script, "\n"), path)
	vim.uv.fs_chmod(path, tonumber("755", 8))
end

-- the stubs write why they refused to work to this file
local stub_log

local function why()
	local lines = vim.fn.filereadable(stub_log) == 1 and vim.fn.uniq(vim.fn.sort(vim.fn.readfile(stub_log))) or {}
	return #lines > 0 and " (stub log: " .. table.concat(lines, "; ") .. ")" or ""
end

local function open(path, lines, filetype)
	if lines then
		vim.fn.writefile(lines, path)
	end
	-- a new tab keeps pending callbacks of the Oil window from touching this buffer
	vim.cmd.tabedit(vim.fn.fnameescape(path))
	if filetype then
		vim.bo.filetype = filetype
	end
	local attached = vim.wait(10000, function()
		return #vim.lsp.get_clients({ bufnr = 0, name = "null-ls" }) > 0
	end, 50)
	assert(attached, "null-ls did not attach to " .. path)
end

-- the diagnostics of a source as lnum:col-end_col/severity, separated by commas
local function marks(source)
	local found = vim.tbl_filter(function(diagnostic)
		return diagnostic.source == source
	end, vim.diagnostic.get(0))
	return table.concat(
		vim.tbl_map(function(diagnostic)
			return ("%d:%d-%d/%d"):format(diagnostic.lnum, diagnostic.col, diagnostic.end_col, diagnostic.severity)
		end, found),
		","
	)
end

-- waits until `source` has one warning at lnum:col-end_col and nothing else (no arguments: no diagnostic)
local function reports(source, lnum, col, end_col)
	local expected = lnum and ("%d:%d-%d/%d"):format(lnum, col, end_col, vim.diagnostic.severity.WARN) or ""
	local found
	local matched = vim.wait(10000, function()
		found = marks(source)
		return found == expected
	end, 50)
	assert(matched, ("%s marks [%s] instead of [%s]%s"):format(source, found, expected, why()))
end

local function last_line(path)
	local lines = vim.fn.readfile(path)
	return lines[#lines]
end

local function formats_on_write(path, marker)
	vim.cmd.write()
	local formatted = vim.wait(10000, function()
		return last_line(path) == marker
	end, 50)
	assert(formatted, "format-on-save did not change " .. path .. why())
end

-- Language setups live in their own specs; each one must have run once its trigger fired.
local function languages()
	assert(vim.env.GOROOT and vim.env.GOPATH, "go-env-setup did not run")
	assert(vim.lsp.is_enabled("nixd"), "nix-lsp-setup did not run")
	assert(
		vim.iter(require("null-ls").get_sources()):any(function(source)
			return source.name == "nixfmt"
		end),
		"nixfmt is not registered"
	)

	local dir = vim.fn.tempname()
	vim.fn.mkdir(dir .. "/bin", "p")
	vim.fn.mkdir(dir .. "/py", "p")
	stub_log = dir .. "/stub.log"
	-- ruff and tflint report their findings as JSON and exit with 1 and 2 like the real tools do when they
	-- found something. ruff reads the buffer from stdin and finds the unused import wherever it is in it;
	-- tflint needs a .tf file in its directory, reports a finding of another file as well and writes to
	-- stderr where a file called noise is; the formatters append a line to what they read. A stub says why
	-- in the log and exits with 3 unless it gets exactly the arguments the source should pass. When libuv
	-- handles the exit of one child it reports all children that have exited, and null-ls stops reading a
	-- command at that report, so output written while the loop was busy is lost: the stubs wait before
	-- they exit.
	local tflint_issue = {
		rule = { name = "unused", severity = "warning" },
		message = "unused",
		range = { filename = "main.tf", start = { line = 1, column = 10 }, ["end"] = { line = 1, column = 13 } },
	}
	local other_issue = vim.tbl_deep_extend("force", tflint_issue, { range = { filename = "other.tf" } })
	local tflint_report = vim.json.encode({ issues = { tflint_issue, other_issue }, errors = {} })
	tool(dir .. "/bin/ruff", "log=" .. stub_log .. [[

case "$*" in
"format --stdin-filename "*" -") cat; echo "# ruff"; sleep 0.5; exit 0 ;;
"check --no-fix --output-format json --stdin-filename "*" -") ;;
*) echo "ruff: unexpected arguments: $*" >> $log; exit 3 ;;
esac
row=$(awk '/import os/ { print NR; exit }')
[ -n "$row" ] || { echo '[]'; sleep 0.5; exit 0; }
printf '[{"code":"F401","message":"unused","location":{"row":%s,"column":8},
"end_location":{"row":%s,"column":10}}]\n' "$row" "$row"
sleep 0.5; exit 1
]])
	tool(dir .. "/bin/terraform", "log=" .. stub_log .. [[

[ "$*" = "fmt -" ] || { echo "terraform: unexpected arguments: $*" >> $log; exit 3; }
cat; echo "# terraform"; sleep 0.5
]])
	tool(dir .. "/bin/tflint", "log=" .. stub_log .. [[

[ "$*" = "--format json" ] || { echo "tflint: unexpected arguments: $*" >> $log; exit 3; }
[ -f main.tf ] || { echo "tflint: no main.tf in $PWD" >> $log; exit 3; }
[ -f noise ] && echo warning >&2
]] .. "echo '" .. tflint_report .. "'; sleep 0.5; exit 2")
	vim.env.PATH = dir .. "/bin:" .. vim.env.PATH
	-- requirements.txt keeps get_ruff_command from looking for a uv project above the temporary directory
	vim.fn.writefile({}, dir .. "/py/requirements.txt")

	open(dir .. "/py/sample.py", { "import os", "x=1" })
	assert(vim.lsp.is_enabled("basedpyright"), "python-lsp-setup did not run")
	reports("ruff", 0, 7, 9)
	-- ruff gets the buffer: an edit that is not saved moves the finding, and one that fixes it clears it
	vim.api.nvim_buf_set_lines(0, 0, 0, false, { "# comment" })
	reports("ruff", 1, 7, 9)
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x=1" })
	reports("ruff")
	formats_on_write(dir .. "/py/sample.py", "# ruff")
	-- a file that is not on disk yet
	open(dir .. "/py/new.py")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "import os" })
	reports("ruff", 0, 7, 9)

	open(dir .. "/main.tf", { 'variable "x" {}' })
	assert(vim.lsp.is_enabled("terraform_ls"), "terraform-lsp-setup did not run")
	reports("tflint", 0, 9, 12)
	formats_on_write(dir .. "/main.tf", "# terraform")
	for _, lhs in ipairs({ "<M-CR>", "<D-S-r>", "<M-S-r>" }) do
		assert(vim.fn.maparg(lhs, "n", false, true).buffer == 1, "terraform keymap " .. lhs .. " is not set")
	end

	vim.fn.mkdir(dir .. "/noisy", "p")
	vim.fn.writefile({}, dir .. "/noisy/noise")
	open(dir .. "/noisy/main.tf", { 'variable "x" {}' })
	reports("tflint", 0, 9, 12)

	-- `nvim new/main.tf` before the directory exists must not make null-ls give up the source
	open(dir .. "/new/main.tf", nil, "terraform")
	vim.wait(1000, function()
		return false
	end, 50)
	vim.fn.mkdir(dir .. "/new", "p")
	formats_on_write(dir .. "/new/main.tf", "# terraform")
	reports("tflint", 0, 9, 12)
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
