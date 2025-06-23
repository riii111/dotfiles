local get_catppuccin_colors = function()
  local has_catppuccin, catppuccin = pcall(require, "catppuccin.palettes")
  if has_catppuccin then
    return catppuccin.get_palette("macchiato")
  else
    return {
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
  end
end

local colors = get_catppuccin_colors()

require("nvim-web-devicons").set_icon {
  lua = { icon = "󰢱", color = colors.blue, name = "Lua" },
  go = { icon = "󰟓", color = "#00ADD8", name = "Go" },
  toml = { icon = "󰿘", color = colors.pink, name = "Toml" },
  dockerfile = { icon = "󰡨", color = colors.blue, name = "Dockerfile" },
  rust = { icon = "󱘗", color = "#D34516", name = "Rust" },
  rs = { icon = "󱘗", color = "#D34516", name = "Rust" },
  js = { icon = "󰌞", color = "#F0DB4F", name = "JavaScript" },
  ts = { icon = "󰛦", color = "#007ACC", name = "TypeScript" },
  json = { icon = "󰘦", color = "#F0DB4F", name = "JSON" },
  yaml = { icon = "󰈙", color = colors.mauve, name = "YAML" },
  yml = { icon = "󰈙", color = colors.mauve, name = "YAML" },
  md = { icon = "󰍔", color = colors.text, name = "Markdown" },
  sql = { icon = "󰆼", color = colors.pink, name = "SQL" },
  py = { icon = "󰌠", color = "#4584B6", name = "Python" },
}

require("nvim-web-devicons").set_default_icon('󰈔', colors.text)

require("nvim-web-devicons").setup {
  override_by_filename = {
    [".gitignore"] = { icon = "", color = colors.overlay0, name = "GitIgnore" },
    ["README.md"] = { icon = "󰍔", color = colors.text, name = "Readme" },
    ["Cargo.toml"] = { icon = "", color = "#D34516", name = "Cargo" },
    ["Cargo.lock"] = { icon = "", color = colors.overlay0, name = "CargoLock" },
    ["go.mod"] = { icon = "󰟓", color = colors.text, name = "GoMod" },
    ["go.sum"] = { icon = "󰟓", color = colors.text, name = "GoSum" },
    ["package.json"] = { icon = "", color = "#F0DB4F", name = "PackageJson" },
    ["package-lock.json"] = { icon = "", color = colors.overlay0, name = "PackageLock" },
    ["tsconfig.json"] = { icon = "", color = "#007ACC", name = "TSConfig" },
  },
  override_by_extension = {
    ["log"] = { icon = "󰌱", color = colors.overlay0, name = "Log" },
  },
  default = true,
  color_icons = true,
}
