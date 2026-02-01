local M = {}

local palette = require("custom-theme-riii111.palette")

function M.apply()
	-- Define theme highlights
	local highlights = {
		-- Base colors (ensuring transparency)
		Normal = { fg = palette.base.fg, bg = palette.base.bg },
		NormalNC = { fg = palette.base.fg, bg = palette.base.bg },
		NormalFloat = { fg = palette.base.fg, bg = palette.base.bg },
		FloatBorder = { fg = palette.base.accent, bg = palette.base.bg },
		SignColumn = { bg = palette.base.bg },
		VertSplit = { fg = palette.base.bg },

		-- Cursor and Line Numbers
		Cursor = { fg = palette.base.white },
		CursorLine = { bg = palette.base.bg_cursor_line },

		-- Pmenu
		Pmenu = { fg = palette.base.fg, bg = palette.base.bg_light },
		PmenuSel = { fg = palette.base.fg_dark, bg = palette.base.accent, bold = true },
		PmenuSbar = { bg = palette.base.bg_light },
		PmenuThumb = { bg = palette.base.accent },

		-- Wildmenu (cmdline completion)
		WildMenu = { fg = palette.base.fg_dark, bg = palette.base.accent, bold = true },

		-- StatusLine & TabLine
		StatusLine = { fg = palette.base.fg, bg = palette.base.bg_light },
		StatusLineNC = { fg = palette.base.fg_alt, bg = palette.base.bg_light },
		TabLine = { fg = palette.base.fg_alt, bg = "NONE" },
		TabLineFill = { bg = "NONE" },
		TabLineSel = { fg = palette.base.fg, bg = palette.base.bg_tab_selected, bold = true },

		-- Search & Visual
		Search = { fg = palette.base.fg_dark, bg = palette.visual.search },
		IncSearch = { fg = palette.base.fg_dark, bg = palette.visual.inc_search },
		Visual = { bg = palette.visual.visual },
		VisualNOS = { bg = palette.visual.visual },

		-- Folding
		Folded = { fg = palette.base.fg_alt, bg = palette.base.bg_light },
		FoldColumn = { fg = palette.syntax.comment },

		-- Messages
		Error = { fg = palette.semantic.error },
		ErrorMsg = { fg = palette.semantic.error },
		WarningMsg = { fg = palette.semantic.warning },

		-- Syntax Groups
		Comment = { fg = palette.syntax.comment, italic = true },
		Constant = { fg = palette.syntax.constant },
		String = { fg = palette.syntax.string },
		Character = { fg = palette.syntax.character },
		Number = { fg = palette.syntax.number },
		Boolean = { fg = palette.syntax.boolean },
		Float = { fg = palette.syntax.float },
		Identifier = { fg = palette.syntax.identifier },
		Function = { fg = palette.syntax.func, italic = true },
		Statement = { fg = palette.base.white },
		Conditional = { fg = palette.syntax.conditional, italic = true },
		Repeat = { fg = palette.syntax.conditional, italic = true },
		Label = { fg = palette.syntax.conditional },
		Operator = { fg = palette.syntax.operator },
		Keyword = { fg = palette.syntax.conditional, italic = true },
		Exception = { fg = palette.syntax.conditional, italic = true },
		PreProc = { fg = palette.syntax.preproc, italic = true },
		Include = { fg = palette.syntax.constant, italic = true },
		Define = { fg = palette.syntax.preproc, italic = true },
		Macro = { fg = palette.syntax.preproc, italic = true },
		PreCondit = { fg = palette.syntax.preproc, italic = true },
		Type = { fg = palette.syntax.type, italic = true },
		Variable = { fg = palette.syntax.variable },
		StorageClass = { fg = palette.syntax.conditional, italic = true },
		Structure = { fg = palette.syntax.type, italic = true },
		Typedef = { fg = palette.syntax.type, italic = true },
		Special = { fg = palette.syntax.special, italic = true },
		SpecialChar = { fg = palette.syntax.special_char },
		Tag = { fg = palette.base.accent, italic = true },
		Delimiter = { fg = palette.syntax.delimiter },
		SpecialComment = { fg = palette.syntax.comment, italic = true },
		Debug = { fg = palette.semantic.warning },
		Underlined = { underline = true },
		Ignore = { fg = palette.base.fg_alt },
		Todo = { fg = palette.base.fg_dark, bg = palette.semantic.warning, bold = true },

		-- Diffs (with background colors for better visibility)
		DiffAdd = { bg = palette.diff.add },
		DiffChange = { bg = palette.diff.change },
		DiffDelete = { bg = palette.diff.delete },
		DiffText = { bg = palette.diff.text },

		-- Indent guideline color adjustment (v3 compatible)
		IndentBlanklineChar = { fg = palette.visual.visual },
		IndentBlanklineContextChar = { fg = palette.syntax.comment },

		-- Diagnostics
		DiagnosticError = { fg = palette.semantic.error },
		DiagnosticWarn = { fg = palette.semantic.warning },
		DiagnosticInfo = { fg = palette.semantic.info },
		DiagnosticHint = { fg = palette.semantic.hint },
		DiagnosticUnderlineError = { undercurl = true, sp = palette.semantic.error },
		DiagnosticUnderlineWarn = { undercurl = true, sp = palette.semantic.warning },
		DiagnosticUnderlineInfo = { undercurl = true, sp = palette.semantic.info },
		DiagnosticUnderlineHint = { undercurl = true, sp = palette.semantic.hint },

		-- TreesitterContext highlight setting for background transparency
		TreesitterContext = { bg = "NONE" },

		-- Directory colors (for various file explorers including Oil.nvim)
		Directory = { fg = palette.devicons.text },

		-- Telescope specific colors (ensure transparency)
		TelescopeBorder = { fg = palette.telescope.border, bg = "NONE" },
		TelescopePromptBorder = { fg = palette.telescope.prompt_border, bg = "NONE" },
		TelescopeResultsBorder = { fg = palette.telescope.results_border, bg = "NONE" },
		TelescopePreviewBorder = { fg = palette.telescope.preview_border, bg = "NONE" },
		TelescopePromptPrefix = { fg = palette.telescope.prompt_prefix },
		TelescopePromptNormal = { fg = palette.telescope.prompt_normal, bg = "NONE" },
		TelescopePromptCounter = { fg = palette.telescope.prompt_counter },
		TelescopeSelectionCaret = { fg = palette.telescope.selection_caret },
		TelescopeSelection = { fg = palette.telescope.selection, bg = palette.telescope.selection_bg, bold = true },
		TelescopeMultiSelection = { fg = palette.telescope.multi_selection, bg = palette.telescope.multi_selection_bg },
		TelescopeMatching = { fg = palette.telescope.matching, bold = true },
		TelescopeNormal = { bg = palette.telescope.normal },
		TelescopeResultsNormal = { bg = palette.telescope.results_normal },
		TelescopePreviewNormal = { bg = palette.telescope.preview_normal },

		-- Diffview specific highlights
		DiffviewDiffAdd = { bg = palette.diffview.diff_add },
		DiffviewDiffChange = { bg = palette.diffview.diff_change },
		DiffviewDiffDelete = { bg = palette.diffview.diff_delete },
		DiffviewDiffText = { bg = palette.diffview.diff_text },
		DiffviewCursorLine = { bg = palette.diffview.cursor_line },
		DiffviewStatusLine = { fg = palette.diffview.status_line, bg = palette.diffview.status_line_bg },
		DiffviewFilePanelTitle = { fg = palette.diffview.file_panel_title, bold = true },
		DiffviewFilePanelCounter = { fg = palette.diffview.file_panel_counter },

		-- Render Markdown code block (darker background)
		RenderMarkdownCode = { bg = palette.base.bg_dark },
		RenderMarkdownCodeInline = { bg = palette.base.bg_dark },

		-- Treesitter specific highlights
		-- Raw/multiline strings (Go raw, Rust raw, JS/TS template, Kotlin multiline)
		["@string.special"] = { fg = palette.syntax.string_raw },

		["@field"] = { fg = palette.base.accent, italic = true },
		["@variable.member.go"] = { fg = palette.syntax.constant, italic = true }, -- Struct exported member
		["@module.rust"] = { fg = palette.base.white },
		["@lsp.type.attributeBracket.rust"] = { fg = palette.base.white },
		["@module.go"] = { fg = palette.base.white },
		["@lsp.type.namespace.go"] = { fg = palette.base.white },

		["@variable.builtin"] = { fg = palette.syntax.constant },
		["@variable.parameter"] = { fg = palette.base.white },
		["@type.builtin"] = { fg = palette.syntax.type_builtin },
		["@type.builtin.go"] = { fg = palette.syntax.type_builtin },
		["@type.builtin.rust"] = { fg = palette.syntax.type_builtin },
		["@lsp.type.variable.go"] = { fg = palette.base.white },
		["@lsp.type.parameter.go"] = { fg = palette.base.white },
		["@constant"] = { fg = palette.syntax.constant },
		["@constant.builtin"] = { fg = palette.syntax.constant },
	}

	-- Apply all defined theme highlights
	for group, attrs in pairs(highlights) do
		vim.api.nvim_set_hl(0, group, attrs)
	end
end

function M.apply_bufferline_overrides()
	if vim.g.colors_name ~= "custom-theme-riii111" then
		return
	end

	local label_fg = palette.base.fg_dark
	local inactive_fg = palette.base.fg_muted

	local lang_groups = {
		{ "Go", palette.languages.go },
		{ "Rs", palette.languages.rust },
		{ "Lua", palette.languages.lua },
		{ "Ts", palette.languages.typescript },
		{ "Tsx", palette.languages.tsx },
		{ "Js", palette.languages.javascript },
		{ "Jsx", palette.languages.jsx },
		{ "C", palette.languages.c },
		{ "Cpp", palette.languages.cpp },
		{ "Kotlin", palette.languages.kotlin },
		{ "Docs", palette.languages.docs },
	}

	for _, group in ipairs(lang_groups) do
		local prefix, lang_color = group[1], group[2]
		vim.api.nvim_set_hl(0, "BufferLine" .. prefix .. "Label", { fg = label_fg, bg = lang_color })
		vim.api.nvim_set_hl(0, "BufferLine" .. prefix .. "Selected", { fg = lang_color, bold = true })
		vim.api.nvim_set_hl(0, "BufferLine" .. prefix, { fg = inactive_fg })
		vim.api.nvim_set_hl(0, "BufferLine" .. prefix .. "Visible", { fg = inactive_fg })
	end
end

return M
