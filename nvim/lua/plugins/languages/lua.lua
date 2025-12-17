return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts = opts or {}
      local ensure = opts.ensure_installed or {}
      if not vim.tbl_contains(ensure, "lua") then
        table.insert(ensure, "lua")
      end
      opts.ensure_installed = ensure
      return opts
    end,
  },
}
