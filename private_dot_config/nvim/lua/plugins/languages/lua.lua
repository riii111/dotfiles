return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      return require("utils.treesitter").extend(opts, {
        languages = { "lua" },
        filetypes = { "lua" },
        indent_filetypes = { "lua" },
      })
    end,
  },
}
