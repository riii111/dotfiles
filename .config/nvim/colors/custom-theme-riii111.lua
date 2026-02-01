-- custom-theme-riii111 colorscheme entry point
-- Usage: :colorscheme custom-theme-riii111

-- P0 fix: Proper colorscheme reset
if vim.g.colors_name then
	vim.cmd("hi clear")
end
if vim.fn.exists("syntax_on") == 1 then
	vim.cmd("syntax reset")
end

require("custom-theme-riii111").load()
