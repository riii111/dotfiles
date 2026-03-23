-- Minimal nvim config for tmux scrollback pager (launched with --clean)
-- Uses terminal buffer to preserve ANSI colors from capture-pane -e

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
    vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], { buffer = true })
    vim.keymap.set("n", "q", "<cmd>quit!<CR>", { buffer = true, nowait = true })

    -- Wait for cat to finish, then position cursor
    local prev_lines = -1
    local function poll()
      local total = vim.api.nvim_buf_line_count(0)
      if total ~= prev_lines then
        prev_lines = total
        vim.defer_fn(poll, 10)
        return
      end
      vim.schedule(do_position)
    end
    vim.schedule(poll)
  end,
})
