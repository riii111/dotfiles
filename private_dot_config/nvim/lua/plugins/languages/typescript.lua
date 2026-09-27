return {
	{
		"neovim/nvim-lspconfig",
		init = function()
			local filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" }

			vim.lsp.config("ts_ls", {
				cmd = { vim.fn.stdpath("data") .. "/mason/bin/typescript-language-server", "--stdio" },
				root_markers = { "package.json", "tsconfig.json", "jsconfig.json", ".git" },
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

			local function start_ts_ls(bufnr)
				if
					not vim.tbl_contains(filetypes, vim.bo[bufnr].filetype)
					or #vim.lsp.get_clients({ bufnr = bufnr, name = "ts_ls" }) > 0
				then
					return
				end

				local config = vim.deepcopy(vim.lsp.config.ts_ls)
				vim.lsp.start(config, {
					bufnr = bufnr,
					reuse_client = config.reuse_client,
					_root_markers = config.root_markers,
				})
			end

			start_ts_ls(0)
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("typescript_lsp", { clear = true }),
				pattern = filetypes,
				callback = function(event)
					start_ts_ls(event.buf)
				end,
			})
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
