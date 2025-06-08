if true then return {} end -- WARN: REMOVE THIS LINE TO ACTIVATE THIS FILE

-- Customize Treesitter

---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "go",
      "rust",
      "python",
      "typescript",
      "javascript",
      "html",
      "css",
      "json",
      "yaml",
      "markdown",
      -- add more arguments for adding more treesitter parsers
    },
    indent = {
      enable = true,
    },
  },
}
