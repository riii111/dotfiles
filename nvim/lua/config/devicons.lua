local unified_colors = require("config.colors")

-- Use devicons specific colors, fallback to unified palette for language colors
local colors = unified_colors.devicons

require("nvim-web-devicons").set_icon {
  lua = { icon = "󰢱", color = colors.blue, name = "Lua" },
  go = { icon = "󰟓", color = unified_colors.languages.go, name = "Go" },
  toml = { icon = "󰿘", color = colors.pink, name = "Toml" },
  dockerfile = { icon = "󰡨", color = colors.blue, name = "Dockerfile" },
  rust = { icon = "󱘗", color = unified_colors.languages.rust, name = "Rust" },
  rs = { icon = "󱘗", color = unified_colors.languages.rust, name = "Rust" },
  js = { icon = "󰌞", color = unified_colors.languages.javascript, name = "JavaScript" },
  ts = { icon = "󰛦", color = unified_colors.languages.typescript, name = "TypeScript" },
  json = { icon = "󰘦", color = unified_colors.languages.javascript, name = "JSON" },
  yaml = { icon = "󰈙", color = colors.mauve, name = "YAML" },
  yml = { icon = "󰈙", color = colors.mauve, name = "YAML" },
  md = { icon = "󰍔", color = colors.text, name = "Markdown" },
  sql = { icon = "󰆼", color = colors.pink, name = "SQL" },
  py = { icon = "󰌠", color = colors.blue, name = "Python" },
}

require("nvim-web-devicons").set_default_icon('󰈔', colors.text)

require("nvim-web-devicons").setup {
  override_by_filename = {
    [".gitignore"] = { icon = "", color = colors.overlay0, name = "GitIgnore" },
    ["README.md"] = { icon = "󰍔", color = colors.text, name = "Readme" },
    ["Cargo.toml"] = { icon = "", color = unified_colors.languages.rust, name = "Cargo" },
    ["Cargo.lock"] = { icon = "", color = colors.overlay0, name = "CargoLock" },
    ["go.mod"] = { icon = "󰟓", color = colors.text, name = "GoMod" },
    ["go.sum"] = { icon = "󰟓", color = colors.text, name = "GoSum" },
    ["package.json"] = { icon = "", color = unified_colors.languages.javascript, name = "PackageJson" },
    ["package-lock.json"] = { icon = "", color = colors.overlay0, name = "PackageLock" },
    ["tsconfig.json"] = { icon = "", color = unified_colors.languages.typescript, name = "TSConfig" },
  },
  override_by_extension = {
    ["log"] = { icon = "󰌱", color = colors.overlay0, name = "Log" },
  },
  default = true,
  color_icons = true,
}
