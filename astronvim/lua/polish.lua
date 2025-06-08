local function apply_flate_arc_italic()
  -- Define theme highlights
  local highlights = {
    -- Base colors (ensuring transparency)
    Normal = { fg = "#e9dbdb", bg = "NONE" },
    NormalNC = { fg = "#e9dbdb", bg = "NONE" },
    NormalFloat = { fg = "#e9dbdb", bg = "#22252f" },
    FloatBorder = { fg = "#00cecb", bg = "NONE" },
    SignColumn = { bg = "NONE" },
    VertSplit = { fg = "NONE" },

    -- Cursor and Line Numbers
    Cursor = { fg = "#ffffff" },
    CursorLine = { bg = "#2f313c" },

    -- Pmenu
    Pmenu = { fg = "#e9dbdb", bg = "#22252f" },
    PmenuSel = { fg = "#e9dbdb", bg = "#00cecb", bold = true },
    PmenuSbar = { bg = "#22252f" },
    PmenuThumb = { bg = "#00cecb" },

    -- StatusLine & TabLine
    StatusLine = { fg = "#e9dbdb", bg = "#22252f" },
    StatusLineNC = { fg = "#9a9fbf", bg = "#22252f" },
    TabLine = { fg = "#9a9fbf", bg = "#22252f" },
    TabLineFill = { bg = "#22252f" },
    TabLineSel = { fg = "#e9dbdb", bg = "NONE", bold = true },

    -- Search & Visual˙
    Search = { fg = "#111419", bg = "#FFE066" },
    IncSearch = { fg = "#111419", bg = "#F49E4C" },
    Visual = { bg = "#44475a" },
    VisualNOS = { bg = "#44475a" },

    -- Folding
    Folded = { fg = "#9a9fbf", bg = "#22252f" },
    FoldColumn = { fg = "#6272A4" },

    -- Messages
    Error = { fg = "#f14c4c" },
    ErrorMsg = { fg = "#f14c4c" },
    WarningMsg = { fg = "#cca700" },

    -- Syntax Groups (Examples)
    Comment = { fg = "#6272A4", italic = true },
    Constant = { fg = "#F0AA85", italic = true, bold = true },
    String = { fg = "#dbdbda" },
    Character = { fg = "#ffffff" },
    Number = { fg = "#ffffff" },
    Boolean = { fg = "#ffffff" },
    Float = { fg = "#ffffff" },
    Identifier = { fg = "#ffffff" },
    Directory = { fg = "#e3e7ef" },
    Function = { fg = "#55CF9E", italic = true },
    Statement = { fg = "#ffffff" },
    Conditional = { fg = "#EC53A0", italic = true },
    Repeat = { fg = "#EC53A0", italic = true },
    Label = { fg = "#EC53A0" },
    Operator = { fg = "#8A91A5" },
    Keyword = { fg = "#EC53A0", italic = true },
    Exception = { fg = "#EC53A0", italic = true },
    PreProc = { fg = "#FF5D8F", italic = true },
    Include = { fg = "#F0AA85", italic = true },
    Define = { fg = "#FF5D8F", italic = true },
    Macro = { fg = "#FF5D8F", italic = true },
    PreCondit = { fg = "#FF5D8F", italic = true },
    Type = { fg = "#17d0cd", italic = true },
    Variable = { fg = "#0a0017" },
    StorageClass = { fg = "#EC53A0", italic = true },
    Structure = { fg = "#17d0cd", italic = true },
    Typedef = { fg = "#17d0cd", italic = true },
    Special = { fg = "#F49E4C", italic = true },
    SpecialChar = { fg = "#C9C9C4" },
    Tag = { fg = "#00cecb", italic = true },
    Delimiter = { fg = "#b7bac4" },
    SpecialComment = { fg = "#6272A4", italic = true },
    Debug = { fg = "#cca700" },
    Underlined = { underline = true },
    Ignore = { fg = "#9a9fbf" },
    Todo = { fg = "#111419", bg = "#cca700", bold = true },

    -- Diffs
    DiffAdd = { fg = "#23D18C" },
    DiffChange = { fg = "#A29BFE" },
    DiffDelete = { fg = "#E84855" },
    DiffText = { fg = "#A29BFE" },

    -- Indent guideline color adjustment (v3 compatible)
    IndentBlanklineChar = { fg = "#44475a" }, -- Regular indent line color
    IndentBlanklineContextChar = { fg = "#6272A4" }, -- Scope/Context indent line color

    -- Diagnostics
    DiagnosticError = { fg = "#f14c4c" },
    DiagnosticWarn = { fg = "#cca700" },
    DiagnosticInfo = { fg = "#3794ff" },
    DiagnosticHint = { fg = "#6bf178" },
    DiagnosticUnderlineError = { undercurl = true, sp = "#f14c4c" },
    DiagnosticUnderlineWarn = { undercurl = true, sp = "#cca700" },
    DiagnosticUnderlineInfo = { undercurl = true, sp = "#3794ff" },
    DiagnosticUnderlineHint = { undercurl = true, sp = "#6bf178" },

    -- NvimTree specific colors (ensure transparency)
    NvimTreeNormal = { fg = "#bccae4", bg = "NONE" },
    NvimTreeNormalNC = { fg = "#bccae4", bg = "NONE" },
    NvimTreeEndOfBuffer = { bg = "NONE" },
    NvimTreeRootFolder = { fg = "#9a9fbf" },
    NvimTreeFolderName = { fg = "#A29BFE" },
    NvimTreeFolderIcon = { fg = "#A29BFE" },
    NvimTreeEmptyFolderName = { fg = "#9a9fbf" },
    NvimTreeOpenedFolderName = { fg = "#00cecb" },
    NvimTreeIndentMarker = { fg = "#8A91A5" },
    NvimTreeGitDirty = { fg = "#F49E4C" },
    NvimTreeGitNew = { fg = "#23D18C" },
    NvimTreeGitDeleted = { fg = "#E84855" },
    NvimTreeWinSeparator = { fg = "#101019", bg = "NONE" },
    NvimTreeCursorLine = { bg = "#22252f" }, -- Adjusted cursor line color

    -- Add TreesitterContext highlight setting for background transparency
    TreesitterContext = { bg = "NONE" },

    -- Neo-Tree specific colors (ensure transparency)
    NeoTreeNormal = { fg = "#bccae4", bg = "NONE" },
    NeoTreeNormalNC = { fg = "#bccae4", bg = "NONE" },
    NeoTreeEndOfBuffer = { bg = "NONE" },
    NeoTreeFileName = { fg = "#D8DEE9" },
    NeoTreeWinSeparator = { fg = "#101019", bg = "NONE" },
    NeoTreeCursorLine = { bg = "#2c2f39" },

    -- Telescope specific colors (ensure transparency)
    TelescopeBorder = { fg = "#00cecb", bg = "NONE" },
    TelescopePromptBorder = { fg = "#00cecb", bg = "NONE" },
    TelescopeResultsBorder = { fg = "#00cecb", bg = "NONE" },
    TelescopePreviewBorder = { fg = "#00cecb", bg = "NONE" },
    TelescopePromptPrefix = { fg = "#00cecb" },
    TelescopePromptNormal = { fg = "#ffffff", bg = "NONE" },
    TelescopePromptCounter = { fg = "#ffffff" },
    TelescopeSelectionCaret = { fg = "#00cecb" },
    TelescopeSelection = { fg = "#e9dbdb", bg = "#22252f" },
    TelescopeNormal = { bg = "NONE" },
    TelescopeResultsNormal = { bg = "NONE" },
    TelescopePreviewNormal = { bg = "NONE" },

    -- Avante warning fix
    AvanteConflictCurrent = { fg = "#e9dbdb", bg = "#22252f" },
    AvanteConflictIncoming = { fg = "#e9dbdb", bg = "#22252f" },

    -- Treesitter specific highlights
    ["@field"] = { fg = "#00cecb", italic = true },
    ["@variable.member.go"] = { fg = "#00cecb", italic = true },
    ["@module.rust"] = { fg = "#ffffff" },
    ["@lsp.type.attributeBracket.rust"] = { fg = "#ffffff" },
    ["@module.go"] = { fg = "#ffffff" },
    ["@lsp.type.namespace.go"] = { fg = "#ffffff" },
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

return {} 
