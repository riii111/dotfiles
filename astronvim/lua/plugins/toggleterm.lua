return {
  "toggleterm.nvim",
  opts = function(_, opts)
    opts.start_in_insert = true
    opts.direction = "horizontal"
    return opts
  end,
  config = function(_, opts)
    require("toggleterm").setup(opts)

    vim.api.nvim_create_autocmd("BufEnter", {
      group = vim.api.nvim_create_augroup("ToggleTermInsertOnEnter", { clear = true }),
      pattern = "term://*",
      callback = function()
        vim.defer_fn(function()
          vim.cmd("startinsert")
        end, 10)
      end,
    })

    vim.api.nvim_create_autocmd("TermOpen", {
      group = vim.api.nvim_create_augroup("ToggleTermUISettings", { clear = true }),
      pattern = "term://*",
      callback = function()
        vim.opt_local.statusline = ""
        vim.opt_local.winfixheight = true
        vim.api.nvim_set_hl(0, "WinSeparator", { fg = "#000000", bg = "NONE" })
      end,
    })
  end,
}
