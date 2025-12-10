return {
  "karb94/neoscroll.nvim",
  event = "VeryLazy",
  config = function()
    local neoscroll = require("neoscroll")
    neoscroll.setup({
      hide_cursor = true,
      stop_eof = true,
      respect_scrolloff = false,
      cursor_scrolls_alone = true,
      easing = "circular",
    })

    local duration = 125

    local keymap = {
      ["<C-u>"] = function() neoscroll.ctrl_u({ duration = duration }) end,
      ["<C-d>"] = function() neoscroll.ctrl_d({ duration = duration }) end,
      ["<C-b>"] = function() neoscroll.ctrl_b({ duration = duration }) end,
      ["<C-f>"] = function() neoscroll.ctrl_f({ duration = duration }) end,
      ["<C-y>"] = function() neoscroll.scroll(-0.1, { move_cursor = false, duration = duration }) end,
      ["<C-e>"] = function() neoscroll.scroll(0.1, { move_cursor = false, duration = duration }) end,
      ["zt"] = function() neoscroll.zt({ half_win_duration = duration }) end,
      ["zz"] = function() neoscroll.zz({ half_win_duration = duration }) end,
      ["zb"] = function() neoscroll.zb({ half_win_duration = duration }) end,
      ["<PageUp>"] = function() neoscroll.ctrl_b({ duration = duration }) end,
      ["<PageDown>"] = function() neoscroll.ctrl_f({ duration = duration }) end,
    }

    local modes = { "n", "v", "x" }
    for key, func in pairs(keymap) do
      vim.keymap.set(modes, key, func, { silent = true })
    end
  end,
}
