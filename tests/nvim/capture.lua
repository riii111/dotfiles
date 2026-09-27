_G.nvim_test_errors = {}
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")

-- lazy.nvim catches configuration errors; record them before they reach a UI notifier.
local util = require("lazy.core.util")
local report = util.error
util.error = function(message, opts)
	table.insert(nvim_test_errors, type(message) == "table" and table.concat(message, "\n") or tostring(message))
	return report(message, opts)
end
