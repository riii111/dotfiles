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
