-- Highlight yanked text (replaces vim-highlightedyank plugin)
local yank_group = vim.api.nvim_create_augroup("highlight_yank", { clear = true })
vim.api.nvim_create_autocmd("TextYankPost", {
  group = yank_group,
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 200 })
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

-- Send git info to WezTerm right status via OSC 2
local wezterm_status = vim.api.nvim_create_augroup("wezterm_status", { clear = true })
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "DirChanged" }, {
  group = wezterm_status,
  callback = function()
    local git_dir = vim.fn.system("git rev-parse --git-dir 2>/dev/null"):gsub("\n", "")
    if vim.v.shell_error ~= 0 then
      local dir = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
      io.write(string.format("\027]2;%s\a", dir))
      return
    end

    local repo = vim.fn.fnamemodify(vim.fn.system("git rev-parse --show-toplevel 2>/dev/null"):gsub("\n", ""), ":t")

    local flags = ""
    local ref = vim.fn.system("git symbolic-ref --short HEAD 2>/dev/null"):gsub("\n", "")
    if vim.v.shell_error ~= 0 then
      ref = vim.fn.system("git rev-parse --short HEAD 2>/dev/null"):gsub("\n", "")
      flags = flags .. "D"
    end

    if vim.fn.system("git status --porcelain 2>/dev/null | head -1"):gsub("\n", "") ~= "" then
      flags = flags .. "d"
    end

    local common_dir = vim.fn.system("git rev-parse --git-common-dir 2>/dev/null"):gsub("\n", "")
    if vim.fn.resolve(git_dir) ~= vim.fn.resolve(common_dir) then
      flags = flags .. "w"
    end

    if vim.fn.isdirectory(git_dir .. "/rebase-merge") == 1 or vim.fn.isdirectory(git_dir .. "/rebase-apply") == 1 then
      flags = flags .. "R"
    end
    if vim.fn.filereadable(git_dir .. "/MERGE_HEAD") == 1 then flags = flags .. "M" end
    if vim.fn.filereadable(git_dir .. "/CHERRY_PICK_HEAD") == 1 then flags = flags .. "C" end

    local title = repo .. "::" .. ref
    if flags ~= "" then title = title .. "::" .. flags end
    io.write(string.format("\027]2;%s\a", title))
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
