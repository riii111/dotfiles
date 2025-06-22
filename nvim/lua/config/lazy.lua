-- Configure lazy.nvim
require("lazy").setup({
  spec = {
    -- Import plugin configurations
    { import = "plugins" },
    { import = "plugins.languages" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  install = { colorscheme = { "habamax" } },
  checker = { enabled = true },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})