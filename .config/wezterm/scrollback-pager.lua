-- Nvim config for WezTerm scrollback pager

vim.o.scrollback = 100000

local function do_position()
  vim.cmd("stopinsert")

  -- Scan backward past trailing empty rows to find last content line
  local total = vim.api.nvim_buf_line_count(0)
  local last_content = 1
  for i = total, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
    if line ~= "" then
      last_content = i
      break
    end
  end

  local win_height = vim.api.nvim_win_get_height(0)
  local topline = math.max(1, last_content - win_height + 1)
  local cursor_x = vim.g.scrollback_cursor_x or 0
  vim.fn.winrestview({ topline = topline, lnum = last_content, col = cursor_x })

  -- G stops at last content line, not empty tail region
  vim.b.scrollback_last_content = last_content
  vim.keymap.set("n", "G", function()
    local lc = vim.b.scrollback_last_content or vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { lc, 0 })
  end, { buffer = true, nowait = true })
end

vim.api.nvim_create_autocmd("TermOpen", {
  once = true,
  callback = function()
    -- Register q immediately so user can exit even during polling
    vim.keymap.set("n", "q", "<cmd>quit!<cr>", { buffer = true, nowait = true })

    local elapsed = 0
    local prev_lines = -1

    local function poll()
      local marker = vim.g.scrollback_marker

      if elapsed >= 3000 then
        -- Timeout: position best-effort
        vim.schedule(do_position)
        return
      end

      if not marker or not vim.loop.fs_stat(marker) then
        elapsed = elapsed + 10
        vim.defer_fn(poll, 10)
        return
      end

      -- Marker found; wait one extra tick for line count to stabilize
      local total = vim.api.nvim_buf_line_count(0)
      if total ~= prev_lines then
        prev_lines = total
        vim.defer_fn(poll, 10)
        return
      end

      vim.loop.fs_unlink(marker, function() end)
      vim.schedule(do_position)
    end

    vim.schedule(poll)
  end,
})
