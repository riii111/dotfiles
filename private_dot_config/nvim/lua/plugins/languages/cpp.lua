return {
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			return require("utils.treesitter").extend(opts, {
				languages = { "c", "cpp", "cmake", "make" },
				filetypes = { "c", "cpp", "cmake", "make" },
				indent_filetypes = { "c", "cpp", "cmake", "make" },
			})
		end,
	},

	{
		"p00f/clangd_extensions.nvim",
		ft = { "c", "cpp", "objc", "objcpp" },
		dependencies = { "neovim/nvim-lspconfig" },
		config = function()
			vim.lsp.config("clangd", {
				cmd = { "clangd", "--background-index", "--clang-tidy" },
				root_markers = { "compile_commands.json", "compile_flags.txt", ".git" },
				init_options = { clangdFileStatus = true },
			})

			vim.lsp.enable("clangd")

			pcall(function()
				require("clangd_extensions").setup({})
			end)

			local ok_null, null_ls = pcall(require, "null-ls")
			if ok_null then
				null_ls.register({
					null_ls.builtins.formatting.clang_format.with({
						filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
					}),
				})
			end

			-- Keymaps: integrate lsp-actions for C/C++
			local lsp_actions = require("utils.lsp-actions")

			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "c", "cpp", "objc", "objcpp" },
				callback = function()
					local opts = { buffer = true, silent = true }

					vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
					vim.keymap.set("n", "<D-S-r>", lsp_actions.cpp_refactor_menu, opts)
					vim.keymap.set("n", "<M-S-r>", lsp_actions.cpp_refactor_menu, opts)
				end,
			})
		end,
	},
}
