-- Minimal nvim config for tmux scrollback pager (launched with --clean)

vim.o.clipboard = "unnamedplus"
vim.o.number = true
vim.o.relativenumber = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.hlsearch = true
vim.o.incsearch = true

-- Yank flash
vim.api.nvim_set_hl(0, "YankFlash", { reverse = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank({ higroup = "YankFlash", timeout = 200 })
  end,
})

-- q to quit (returns to previous tmux window)
vim.keymap.set("n", "q", "<cmd>quit!<CR>", { nowait = true })

-- Position cursor at end of content
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local total = vim.api.nvim_buf_line_count(0)
    local last_content = total
    for i = total, 1, -1 do
      local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
      if line ~= "" then
        last_content = i
        break
      end
    end
    local win_height = vim.api.nvim_win_get_height(0)
    local topline = math.max(1, last_content - win_height + 1)
    vim.fn.winrestview({ topline = topline, lnum = last_content, col = 0 })
  end,
})
