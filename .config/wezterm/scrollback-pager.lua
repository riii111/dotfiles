-- Nvim config for WezTerm scrollback pager

vim.o.scrollback = 100000

-- Wait for cat to finish rendering, then position viewport
vim.defer_fn(function()
  vim.cmd("stopinsert")

  -- Find last non-empty line
  local total = vim.api.nvim_buf_line_count(0)
  local last_content = 1
  for i = total, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
    if line ~= "" then
      last_content = i
      break
    end
  end

  -- Replicate terminal viewport position
  local win_height = vim.api.nvim_win_get_height(0)
  local topline = math.max(1, last_content - win_height + 1)
  local cursor_x = vim.g.scrollback_cursor_x or 0
  vim.fn.winrestview({ topline = topline, lnum = last_content, col = cursor_x })

  -- Remap G to stop at last content line, not empty tail region
  vim.b.scrollback_last_content = last_content
  vim.keymap.set("n", "G", function()
    local lc = vim.b.scrollback_last_content or vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { lc, 0 })
  end, { buffer = true, nowait = true })

  vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = true, nowait = true })
end, 50)
