local M = {}

-- Base Color Palette
M.base = {
  -- Core Colors
  white = "#ffffff",
  black = "#000000",
  transparent = "NONE",

  -- Main Text Colors
  fg = "#e9dbdb",
  fg_alt = "#9a9fbf",
  fg_muted = "#5c6370",
  fg_dark = "#111419",

  -- Background Colors
  bg = "NONE",  -- transparent
  bg_dark = "#16181f",
  bg_medium = "#1a1e26",
  bg_light = "#22252f",
  bg_cursor_line = "#2f313c",
  bg_tab_selected = "#2c2f39",
  bg_accent = "#30344B",
  bg_accent_alt = "#1e222a",
  bg_very_dark = "#08090D",

  -- Accent Colors
  accent = "#00cecb",
  accent_alt = "#192342",
}

-- Semantic Colors  
M.semantic = {
  error = "#f14c4c",
  warning = "#cca700",
  info = "#3794ff",
  hint = "#6bf178",
  success = "#9ece6a",
}

-- Language Specific Colors(GitHub Linguist colors)
M.languages = {
  c = "#555555",
  cpp = "#F34B7D",
  rust = "#DEA584",
  go = "#00ADDB",
  kotlin = "#A97BFF",
  -- Lua: GitHub color (#000080) is too dark on our dark UI; brighten for legibility
  lua = "#3D59FF",
  typescript = "#2B7489",
  javascript = "#F1E05A",
  -- Map JSX/TSX to their parent language colors
  jsx = "#F1E05A",
  tsx = "#2B7489",
  docs = "#54B399",
}

-- Syntax Colors
M.syntax = {
  comment = "#6272A4",
  constant = "#F0AA85",
  string = "#CDC8DB",
  character = "#F0AA85",
  number = "#F0AA85",
  boolean = "#F0AA85",
  float = "#F0AA85",
  identifier = "#ffffff",
  func = "#55CF9E",
  statement = "#ffffff",
  conditional = "#EC53A0",
  repeat_kw = "#EC53A0",
  label = "#EC53A0",
  operator = "#8A91A5",
  keyword = "#EC53A0",
  exception = "#EC53A0",
  preproc = "#FF5D8F",
  include = "#F0AA85",
  define = "#FF5D8F",
  macro = "#FF5D8F",
  precondit = "#FF5D8F",
  type = "#17d0cd",
  type_builtin = "#CC7832",
  variable = "#0a0017",
  storage_class = "#EC53A0",
  structure = "#17d0cd",
  typedef = "#17d0cd",
  special = "#F49E4C",
  special_char = "#C9C9C4",
  tag = "#00cecb",
  delimiter = "#b7bac4",
  special_comment = "#6272A4",
  debug = "#cca700",
  ignore = "#9a9fbf",
  todo_bg = "#cca700",
}

-- Diff Colors
M.diff = {
  add = "#1e3a2e",
  change = "#2d2a3e",
  delete = "#3e2929",
  text = "#3e2a5e",
}

-- Search & Visual
M.visual = {
  search = "#FFE066",
  inc_search = "#F49E4C",
  visual = "#44475a",
  visual_nos = "#44475a",
}

-- Lualine Color Palette
M.lualine = {
  -- Base theme colors
  bg = "#24283b",
  fg = "#c0caf5",
  yellow = "#e0af68",
  cyan = "#7dcfff",
  green = "#73daca",
  orange = "#ff9e64",
  violet = "#9d7cd8",
  magenta = "#a9a1e1",
  blue = "#7aa2f7",
  red = "#f7768e",

  -- Mode colors (refreshed)
  mode_normal = "#7aa2f7",   -- calm blue
  mode_insert = "#73daca",   -- teal green
  mode_visual = "#c678dd",   -- purple
  mode_replace = "#f7768e",  -- coral red
  mode_command = "#e0af68",  -- warm yellow

  -- Git colors
  git = {
    add = "#9ece6a",
    change = "#e0af68",
    delete = "#f7768e",
  },

  -- Mode specific colors
  normal_a = "#1a1e29",
  normal_b = "#e9dbdb",
  normal_c = "#e9dbdb",
  normal_bg_b = "#3b4261",
  normal_bg_c = "#16181f",

  section_b_bg = "#363147",     -- branch
  section_c_bg = "#2d3149",     -- file
  section_y_bg = "#3b4261",     -- right info
  section_z_bg = "#24283b",     -- right end
}

-- DevIcons Colors
M.devicons = {
  -- Catppuccin inspired palette
  blue = "#7da6ff",
  green = "#7ece9c",
  peach = "#f5a97f",
  yellow = "#eed49f",
  pink = "#f5bde6",
  mauve = "#c6a0f6",
  text = "#cad3f5",
  subtext0 = "#a5adcb",
  surface0 = "#363a4f",
  overlay0 = "#6e738d",
}

-- Terminal Colors
M.terminal = {
  normal = "NONE",
  normal_float = "NONE",
  float_border = M.base.accent,
}

-- Telescope Colors
M.telescope = {
  border = M.base.accent,
  prompt_border = M.base.accent,
  results_border = M.base.accent,
  preview_border = M.base.accent,
  prompt_prefix = M.base.accent,
  prompt_normal = M.base.white,
  prompt_counter = M.base.white,
  selection_caret = M.base.accent,
  selection = M.base.white,
  selection_bg = "#3c4048",
  multi_selection = M.base.accent,
  multi_selection_bg = M.base.bg_accent,
  matching = "#f5a97f",
  normal = "NONE",
  results_normal = "NONE",
  preview_normal = "NONE",
}

-- Diffview Colors
M.diffview = {
  diff_add = M.diff.add,
  diff_change = M.diff.change,
  diff_delete = M.diff.delete,
  diff_text = M.diff.text,
  cursor_line = M.visual.visual,
  status_line = M.base.fg,
  status_line_bg = M.base.bg_light,
  file_panel_title = M.base.accent,
  file_panel_counter = "#A29BFE",
}

return M
