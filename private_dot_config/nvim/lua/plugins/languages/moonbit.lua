return {
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			vim.api.nvim_create_autocmd("User", {
				pattern = "TSUpdate",
				callback = function()
					require("nvim-treesitter.parsers").moonbit = {
						install_info = {
							url = "https://github.com/moonbitlang/tree-sitter-moonbit",
							revision = "5435c307c6cf2ef0d508a99047b06f35a4308444",
							queries = "queries",
						},
						tier = 2,
					}
				end,
			})
			return require("utils.treesitter").extend(opts, {
				languages = { "moonbit" },
				filetypes = { "moonbit" },
			})
		end,
	},
	{
		"moonbit-lsp-setup",
		virtual = true,
		ft = { "moonbit" },
		cond = not vim.g.vscode,
		dependencies = { "neovim/nvim-lspconfig", "saghen/blink.cmp" },
		init = function()
			vim.filetype.add({
				extension = { mbt = "moonbit", mbti = "moonbit", mbtx = "moonbit" },
				filename = { ["moon.mod"] = "moonbit", ["moon.pkg"] = "moonbit" },
			})
		end,
		config = function()
			local moon = vim.fn.exepath("moon")
			if moon == "" then
				moon = vim.fs.joinpath(vim.env.MOON_HOME or vim.fn.expand("~/.moon"), "bin", "moon")
			end
			vim.lsp.config("moonbit", {
				cmd = { moon, "lsp", "--stdio" },
				cmd_env = { PATH = vim.fs.dirname(moon) .. ":" .. vim.env.PATH },
				filetypes = { "moonbit" },
				root_markers = { "moon.work", { "moon.mod", "moon.mod.json" }, ".git" },
				capabilities = require("blink.cmp").get_lsp_capabilities(),
				on_attach = function(_, bufnr)
					vim.keymap.set("n", "<M-CR>", require("utils.lsp-actions").language_specific_code_action, {
						buffer = bufnr,
						silent = true,
					})
				end,
			})
			vim.lsp.enable("moonbit")
		end,
	},
}
