local colors = require("config.colors")

local function apply_flate_arc_italic()
  -- Define theme highlights
  local highlights = {
    -- Base colors (ensuring transparency)
    Normal = { fg = colors.base.fg, bg = colors.base.bg },
    NormalNC = { fg = colors.base.fg, bg = colors.base.bg },
    NormalFloat = { fg = colors.base.fg, bg = colors.base.bg },
    FloatBorder = { fg = colors.base.accent, bg = colors.base.bg },
    SignColumn = { bg = colors.base.bg },
    VertSplit = { fg = colors.base.bg },

    -- Cursor and Line Numbers
    Cursor = { fg = colors.base.white },
    CursorLine = { bg = colors.base.bg_cursor_line },

    -- Pmenu
    Pmenu = { fg = colors.base.fg, bg = colors.base.bg_light },
    PmenuSel = { fg = colors.base.fg_dark, bg = colors.base.accent, bold = true },
    PmenuSbar = { bg = colors.base.bg_light },
    PmenuThumb = { bg = colors.base.accent },

    -- Wildmenu (cmdline completion)
    WildMenu = { fg = colors.base.fg_dark, bg = colors.base.accent, bold = true },

    -- StatusLine & TabLine
    StatusLine = { fg = colors.base.fg, bg = colors.base.bg_light },
    StatusLineNC = { fg = colors.base.fg_alt, bg = colors.base.bg_light },
    TabLine = { fg = colors.base.fg_alt, bg = colors.base.bg_very_dark },
    TabLineFill = { bg = colors.base.bg_very_dark },
    TabLineSel = { fg = colors.base.fg, bg = colors.base.bg_tab_selected, bold = true },

    -- Search & Visual
    Search = { fg = colors.base.fg_dark, bg = colors.visual.search },
    IncSearch = { fg = colors.base.fg_dark, bg = colors.visual.inc_search },
    Visual = { bg = colors.visual.visual },
    VisualNOS = { bg = colors.visual.visual },

    -- Folding
    Folded = { fg = colors.base.fg_alt, bg = colors.base.bg_light },
    FoldColumn = { fg = colors.syntax.comment },

    -- Messages
    Error = { fg = colors.semantic.error },
    ErrorMsg = { fg = colors.semantic.error },
    WarningMsg = { fg = colors.semantic.warning },

    -- Syntax Groups
    Comment = { fg = colors.syntax.comment, italic = true },
    Constant = { fg = colors.syntax.constant },
    String = { fg = colors.syntax.string },
    Character = { fg = colors.syntax.character },
    Number = { fg = colors.syntax.number },
    Boolean = { fg = colors.syntax.boolean },
    Float = { fg = colors.syntax.float },
    Identifier = { fg = colors.syntax.identifier },
    Function = { fg = colors.syntax.func, italic = true },
    Statement = { fg = colors.base.white },
    Conditional = { fg = colors.syntax.conditional, italic = true },
    Repeat = { fg = colors.syntax.conditional, italic = true },
    Label = { fg = colors.syntax.conditional },
    Operator = { fg = colors.syntax.operator },
    Keyword = { fg = colors.syntax.conditional, italic = true },
    Exception = { fg = colors.syntax.conditional, italic = true },
    PreProc = { fg = colors.syntax.preproc, italic = true },
    Include = { fg = colors.syntax.constant, italic = true },
    Define = { fg = colors.syntax.preproc, italic = true },
    Macro = { fg = colors.syntax.preproc, italic = true },
    PreCondit = { fg = colors.syntax.preproc, italic = true },
    Type = { fg = colors.syntax.type, italic = true },
    Variable = { fg = colors.syntax.variable },
    StorageClass = { fg = colors.syntax.conditional, italic = true },
    Structure = { fg = colors.syntax.type, italic = true },
    Typedef = { fg = colors.syntax.type, italic = true },
    Special = { fg = colors.syntax.special, italic = true },
    SpecialChar = { fg = colors.syntax.special_char },
    Tag = { fg = colors.base.accent, italic = true },
    Delimiter = { fg = colors.syntax.delimiter },
    SpecialComment = { fg = colors.syntax.comment, italic = true },
    Debug = { fg = colors.semantic.warning },
    Underlined = { underline = true },
    Ignore = { fg = colors.base.fg_alt },
    Todo = { fg = colors.base.fg_dark, bg = colors.semantic.warning, bold = true },

    -- Diffs (with background colors for better visibility)
    DiffAdd = { bg = colors.diff.add },
    DiffChange = { bg = colors.diff.change },
    DiffDelete = { bg = colors.diff.delete },
    DiffText = { bg = colors.diff.text },

    -- Indent guideline color adjustment (v3 compatible)
    IndentBlanklineChar = { fg = colors.visual.visual },
    IndentBlanklineContextChar = { fg = colors.syntax.comment },

    -- Diagnostics
    DiagnosticError = { fg = colors.semantic.error },
    DiagnosticWarn = { fg = colors.semantic.warning },
    DiagnosticInfo = { fg = colors.semantic.info },
    DiagnosticHint = { fg = colors.semantic.hint },
    DiagnosticUnderlineError = { undercurl = true, sp = colors.semantic.error },
    DiagnosticUnderlineWarn = { undercurl = true, sp = colors.semantic.warning },
    DiagnosticUnderlineInfo = { undercurl = true, sp = colors.semantic.info },
    DiagnosticUnderlineHint = { undercurl = true, sp = colors.semantic.hint },

    -- TreesitterContext highlight setting for background transparency
    TreesitterContext = { bg = "NONE" },

    -- Directory colors (for various file explorers including Oil.nvim)
    Directory = { fg = colors.devicons.text },

    -- Telescope specific colors (ensure transparency)
    TelescopeBorder = { fg = colors.telescope.border, bg = "NONE" },
    TelescopePromptBorder = { fg = colors.telescope.prompt_border, bg = "NONE" },
    TelescopeResultsBorder = { fg = colors.telescope.results_border, bg = "NONE" },
    TelescopePreviewBorder = { fg = colors.telescope.preview_border, bg = "NONE" },
    TelescopePromptPrefix = { fg = colors.telescope.prompt_prefix },
    TelescopePromptNormal = { fg = colors.telescope.prompt_normal, bg = "NONE" },
    TelescopePromptCounter = { fg = colors.telescope.prompt_counter },
    TelescopeSelectionCaret = { fg = colors.telescope.selection_caret },
    TelescopeSelection = { fg = colors.telescope.selection, bg = colors.telescope.selection_bg, bold = true },
    TelescopeMultiSelection = { fg = colors.telescope.multi_selection, bg = colors.telescope.multi_selection_bg },
    TelescopeMatching = { fg = colors.telescope.matching, bold = true },
    TelescopeNormal = { bg = colors.telescope.normal },
    TelescopeResultsNormal = { bg = colors.telescope.results_normal },
    TelescopePreviewNormal = { bg = colors.telescope.preview_normal },

    -- Diffview specific highlights
    DiffviewDiffAdd = { bg = colors.diffview.diff_add },
    DiffviewDiffChange = { bg = colors.diffview.diff_change },
    DiffviewDiffDelete = { bg = colors.diffview.diff_delete },
    DiffviewDiffText = { bg = colors.diffview.diff_text },
    DiffviewCursorLine = { bg = colors.diffview.cursor_line },
    DiffviewStatusLine = { fg = colors.diffview.status_line, bg = colors.diffview.status_line_bg },
    DiffviewFilePanelTitle = { fg = colors.diffview.file_panel_title, bold = true },
    DiffviewFilePanelCounter = { fg = colors.diffview.file_panel_counter },

    -- Treesitter specific highlights
    ["@field"] = { fg = colors.base.accent, italic = true },
    ["@variable.member.go"] = { fg = colors.syntax.constant, italic = true }, -- Struct exported member
    ["@module.rust"] = { fg = colors.base.white },
    ["@lsp.type.attributeBracket.rust"] = { fg = colors.base.white },
    ["@module.go"] = { fg = colors.base.white },
    ["@lsp.type.namespace.go"] = { fg = colors.base.white },

    ["@variable.builtin"] = { fg = colors.syntax.constant },
    ["@variable.parameter"] = { fg = colors.base.white },
    ["@type.builtin"] = { fg = colors.syntax.type_builtin },
    ["@type.builtin.go"] = { fg = colors.syntax.type_builtin },
    ["@type.builtin.rust"] = { fg = colors.syntax.type_builtin },
    ["@lsp.type.variable.go"] = { fg = colors.base.white },
    ["@lsp.type.parameter.go"] = { fg = colors.base.white },
    ["@constant"] = { fg = colors.syntax.constant },
    ["@constant.builtin"] = { fg = colors.syntax.constant },
  }

  -- Apply all defined theme highlights
  for group, attrs in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, attrs)
  end
end

-- Apply theme immediately on load
apply_flate_arc_italic()

-- Ensure theme and transparency are reapplied after colorscheme changes
vim.api.nvim_create_autocmd("ColorScheme", {
  pattern = "*",
  callback = function()
    apply_flate_arc_italic()
  end,
  group = vim.api.nvim_create_augroup("UserThemeApply", { clear = true }),
})
