local M = {}

local function ensure_list(tbl, key)
	tbl[key] = tbl[key] or {}
	return tbl[key]
end

function M.extend(opts, spec)
	opts = opts or {}
	spec = spec or {}

	for key, values in pairs(spec) do
		local list = ensure_list(opts, key)
		for _, value in ipairs(values) do
			if not vim.tbl_contains(list, value) then
				table.insert(list, value)
			end
		end
	end

	return opts
end

function M.resolve_languages(languages)
	local parsers = require("nvim-treesitter.parsers")
	local resolved = {}
	local ordered = {}

	local function add(language)
		if resolved[language] then
			return
		end
		resolved[language] = true
		table.insert(ordered, language)

		local parser = parsers[language]
		for _, dependency in ipairs((parser and parser.requires) or {}) do
			add(dependency)
		end
	end

	for _, language in ipairs(languages or {}) do
		add(language)
	end

	return ordered
end

function M.start(bufnr, indent_filetypes)
	local filetype = vim.bo[bufnr].filetype
	local ok = pcall(vim.treesitter.start, bufnr)
	if not ok then
		return
	end

	indent_filetypes = indent_filetypes or {}
	if vim.tbl_contains(indent_filetypes, filetype) then
		vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
	end
end

return M
