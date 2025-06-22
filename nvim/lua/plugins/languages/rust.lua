return {
  {
    "mrcjkb/rustaceanvim",
    version = "^5",
    lazy = false,
    ft = { "rust" },
    config = function()
      vim.g.rustaceanvim = {
        server = {
          settings = {
            ["rust-analyzer"] = {
              linkedProjects = vim.NIL,
              cargo = {
                features = "all",
              },
              procMacro = {
                enable = true,
              },
            },
          },
        },
      }
    end,
  },

  {
    "saecki/crates.nvim",
    tag = "stable",
    config = function()
      require("crates").setup()
    end,
    ft = { "toml" },
  },
}