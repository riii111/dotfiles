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

    local function move_and_center(cmd)
      return function()
        local ok, _ = pcall(vim.cmd, "normal! " .. cmd)
        if ok then
          neoscroll.zz({ half_win_duration = duration })
        end
      end
    end

    local function search_and_center(cmd)
      return function()
        vim.cmd("normal! " .. cmd)
        local ok, hlslens = pcall(require, "hlslens")
        if ok then
          hlslens.start()
        end
        neoscroll.zz({ half_win_duration = duration })
      end
    end

    local function search_count_and_center(cmd)
      return function()
        vim.cmd("execute('normal! ' . v:count1 . '" .. cmd .. "')")
        local ok, hlslens = pcall(require, "hlslens")
        if ok then
          hlslens.start()
        end
        neoscroll.zz({ half_win_duration = duration })
      end
    end

    -- Search and navigation with centering
    local search_mappings = {
      ["n"] = search_count_and_center("n"),
      ["N"] = search_count_and_center("N"),
      ["*"] = search_and_center("*"),
      ["#"] = search_and_center("#"),
      ["g*"] = search_and_center("g*"),
      ["g#"] = search_and_center("g#"),
      ["%"] = move_and_center("%"),
    }

    for key, func in pairs(search_mappings) do
      vim.keymap.set("n", key, func, { silent = true })
    end

    -- Jump commands with centering
    local jump_mappings = {
      ["gg"] = function()
        vim.cmd("execute('normal! ' . v:count1 . 'gg')")
        neoscroll.zz({ half_win_duration = duration })
      end,
      ["G"] = move_and_center("G"),
      ["{"] = move_and_center("{"),
      ["}"] = move_and_center("}"),
      ["<C-o>"] = move_and_center("<C-o>"),
      ["<C-i>"] = move_and_center("<C-i>"),
    }

    for key, func in pairs(jump_mappings) do
      vim.keymap.set("n", key, func, { silent = true })
    end
  end,
}
