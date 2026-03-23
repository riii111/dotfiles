-- Nvim config for WezTerm scrollback pager

vim.o.scrollback = 100000
vim.o.clipboard = "unnamedplus"
vim.o.cursorline = true
vim.o.laststatus = 0
vim.o.ruler = false

vim.opt.rtp:append(vim.fn.expand("~/.config/nvim"))
pcall(vim.cmd.colorscheme, "custom-theme-riii111")

vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
})

local function do_position()
  vim.cmd("stopinsert")

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

-- Prompt highlight & jump
vim.api.nvim_set_hl(0, "PromptLine", { underline = true, sp = "#565f89" })
vim.fn.matchadd("PromptLine", "\\S\\+ % .*")
local PROMPT_PATTERN = "%S+ %% "
local function jump_prompt(dir)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local total = vim.api.nvim_buf_line_count(0)
  local step = dir == "prev" and -1 or 1
  local i = row + step
  while i >= 1 and i <= total do
    local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
    if line:match(PROMPT_PATTERN) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return
    end
    i = i + step
  end
end
vim.keymap.set("n", "[p", function() jump_prompt("prev") end)
vim.keymap.set("n", "]p", function() jump_prompt("next") end)

vim.api.nvim_create_autocmd("TermOpen", {
  once = true,
  callback = function()
    vim.keymap.set("n", "q", function()
      local tab_id = vim.g.scrollback_prev_tab
      if tab_id then
        vim.system({ "/opt/homebrew/bin/wezterm", "cli", "activate-tab", "--tab-id", tostring(tab_id) }, { detach = true })
      end
      vim.cmd("quit!")
    end, { buffer = true, nowait = true })

    local elapsed = 0
    local prev_lines = -1

    local function poll()
      local marker = vim.g.scrollback_marker

      if elapsed >= 3000 then
        vim.schedule(do_position)
        return
      end

      if not marker or not vim.loop.fs_stat(marker) then
        elapsed = elapsed + 10
        vim.defer_fn(poll, 10)
        return
      end

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
