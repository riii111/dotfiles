-- Nvim config for WezTerm scrollback pager

vim.o.scrollback = 100000

-- Timer instead of TermClose because tail -f keeps the process alive
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

  vim.keymap.set("n", "q", "<cmd>bd!<cr>", { buffer = true, nowait = true })
end, 200)
