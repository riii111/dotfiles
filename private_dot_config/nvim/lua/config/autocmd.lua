-- Highlight yanked text (replaces vim-highlightedyank plugin)
local yank_group = vim.api.nvim_create_augroup("highlight_yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = yank_group,
  callback = function()
    vim.hl.on_yank({ higroup = "IncSearch", timeout = 200 })
  end,
})

-- Auto-toggle relative line numbers based on mode
local augroup = vim.api.nvim_create_augroup("numbertoggle", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "InsertLeave", "CmdlineLeave", "WinEnter" }, {
  pattern = "*",
  group = augroup,
  callback = function()
    if vim.o.nu and vim.api.nvim_get_mode().mode ~= "i" then
      vim.opt.relativenumber = true
      vim.opt.cursorline = true
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufLeave", "FocusLost", "InsertEnter", "CmdlineEnter", "WinLeave" }, {
  pattern = "*",
  group = augroup,
  callback = function()
    if vim.o.nu then
      vim.opt.relativenumber = false
      vim.opt.cursorline = true
      vim.cmd("redraw")
    end
  end,
})

-- Diagnostic display configuration (applied after all plugins load)
local diagnostic_group = vim.api.nvim_create_augroup("diagnostic_config", { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
  group = diagnostic_group,
  callback = function()
    vim.diagnostic.config({
      virtual_text = {
        format = function(diagnostic)
          local source = diagnostic.source or "unknown"
          local message = diagnostic.message
          if #message > 60 then
            message = message:sub(1, 57) .. "..."
          end
          return string.format("[%s] %s", source, message)
        end,
      },
      float = {
        source = true,
        border = "rounded",
        format = function(diagnostic)
          local source = diagnostic.source or "unknown"
          local code = diagnostic.code and string.format(" (%s)", diagnostic.code) or ""
          return string.format("[%s]%s %s", source, code, diagnostic.message)
        end,
      },
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
    })
  end,
})

-- Async format on save (non-blocking)
local format_ok, format = pcall(require, "utils.format")
if format_ok then
  local format_group = vim.api.nvim_create_augroup("async_format_on_save", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = format_group,
    callback = function(args)
      format.async_format(args.buf)
    end,
  })
end

-- Send git info to WezTerm right status via OSC 2 (async + debounced)
local wezterm_status = vim.api.nvim_create_augroup("wezterm_status", { clear = true })
local _wezterm_timer = vim.uv.new_timer()

local _git_info_script = [[
toplevel=$(git rev-parse --show-toplevel) || exit 1
git_dir=$(git rev-parse --git-dir)
ref=$(git symbolic-ref --short HEAD 2>/dev/null) && detached=0 || { ref=$(git rev-parse --short HEAD); detached=1; }
dirty=$(git status --porcelain | head -1)
common=$(git rev-parse --git-common-dir)
flags=""
[ "$detached" = 1 ] && flags="${flags}D"
[ -n "$dirty" ] && flags="${flags}d"
[ "$(realpath "$git_dir")" != "$(realpath "$common")" ] && flags="${flags}w"
{ [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; } && flags="${flags}R"
[ -f "$git_dir/MERGE_HEAD" ] && flags="${flags}M"
[ -f "$git_dir/CHERRY_PICK_HEAD" ] && flags="${flags}C"
repo="${toplevel##*/}"
title="${repo}::${ref}"
[ -n "$flags" ] && title="${title}::${flags}"
printf '%s\n' "$title"
]]

local function _update_wezterm_title()
  local cwd = vim.fn.getcwd()

  vim.system({ "sh", "-c", _git_info_script }, { cwd = cwd }, function(out)
    local title
    if out.code ~= 0 then
      title = cwd:match("[^/]+$") or cwd
    else
      title = vim.trim(out.stdout)
    end
    io.write(string.format("\027]2;%s\a", title))
  end)
end

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "DirChanged" }, {
  group = wezterm_status,
  callback = function()
    _wezterm_timer:stop()
    _wezterm_timer:start(200, 0, vim.schedule_wrap(_update_wezterm_title))
  end,
})

-- KotlinCompileDaemon has 2-hour idle timeout (not configurable: KT-50510)
-- Kill daemons on exit to prevent memory bloat from zombie processes
local daemon_cleanup = vim.api.nvim_create_augroup("daemon_cleanup", { clear = true })
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = daemon_cleanup,
  callback = function()
    local had_kotlin = false
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[buf].filetype == "kotlin" then
        had_kotlin = true
        break
      end
    end

    if had_kotlin then
      vim.fn.jobstart({ "pkill", "-f", "KotlinCompileDaemon" }, { detach = true })
      vim.fn.jobstart({ "pkill", "-f", "GradleDaemon" }, { detach = true })
    end
  end,
})
