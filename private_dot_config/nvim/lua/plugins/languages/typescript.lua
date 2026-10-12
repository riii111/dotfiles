return {
	{
		"neovim/nvim-lspconfig",
		init = function()
			vim.lsp.config("ts_ls", {
				cmd = { vim.fn.stdpath("data") .. "/mason/bin/typescript-language-server", "--stdio" },
				on_attach = function(client)
					client.server_capabilities.semanticTokensProvider = nil
				end,
				settings = {
					typescript = {
						inlayHints = {
							includeInlayParameterNameHints = "none",
							includeInlayParameterNameHintsWhenArgumentMatchesName = false,
							includeInlayFunctionParameterTypeHints = false,
							includeInlayVariableTypeHints = false,
							includeInlayVariableTypeHintsWhenTypeMatchesName = false,
							includeInlayPropertyDeclarationTypeHints = false,
							includeInlayFunctionLikeReturnTypeHints = false,
							includeInlayEnumMemberValueHints = false,
						},
						suggest = {
							includeCompletionsForModuleExports = true,
						},
						format = {
							enable = false,
						},
					},
					javascript = {
						inlayHints = {
							includeInlayParameterNameHints = "none",
							includeInlayParameterNameHintsWhenArgumentMatchesName = false,
							includeInlayFunctionParameterTypeHints = false,
							includeInlayVariableTypeHints = false,
							includeInlayVariableTypeHintsWhenTypeMatchesName = false,
							includeInlayPropertyDeclarationTypeHints = false,
							includeInlayFunctionLikeReturnTypeHints = false,
							includeInlayEnumMemberValueHints = false,
						},
						suggest = {
							includeCompletionsForModuleExports = true,
						},
						format = {
							enable = false,
						},
					},
				},
			})

			vim.lsp.enable("ts_ls")
			vim.lsp.config("biome", {
				filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact", "json", "jsonc" },
			})
			vim.lsp.enable("biome")
		end,
		config = function()
			-- Keymaps (IntelliJ-like actions)
			local lsp_actions_ok, lsp_actions = pcall(require, "utils.lsp-actions")
			if lsp_actions_ok then
				vim.api.nvim_create_autocmd("FileType", {
					pattern = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
					callback = function()
						local opts = { buffer = true, silent = true }
						vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
						vim.keymap.set("n", "<D-S-r>", lsp_actions.typescript_refactor_menu, opts)
						vim.keymap.set("n", "<M-S-r>", lsp_actions.typescript_refactor_menu, opts)
					end,
				})
			end
		end,
	},
}
