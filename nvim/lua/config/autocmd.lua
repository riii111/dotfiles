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
