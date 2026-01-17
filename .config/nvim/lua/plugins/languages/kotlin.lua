return {
	-- Kotlin LSP configuration (riii111/kotlin-language-server fork)
	-- NOTE: Using a wrapper plugin instead of extending "neovim/nvim-lspconfig" directly
	--       because lazy.nvim may skip this config function when lspconfig is already loaded
	--       by plugins/lsp.lua. A separate plugin name ensures this config always runs.
	--
	-- SETUP: Using forked kotlin-language-server with fixes for generated code (e.g., jOOQ) definition jump.
	--        The fork is built locally and symlinked to ~/.local/bin/kotlin-language-server
	--        See: https://github.com/riii111/kotlin-language-server
	--        Build: cd <fork-repo> && ./gradlew :server:installDist
	--        Symlink: ln -sf <fork-repo>/server/build/install/server/bin/kotlin-language-server ~/.local/bin/
	{
		name = "kotlin-lsp-setup",
		dir = vim.fn.stdpath("config") .. "/lua/plugins/languages",
		lazy = false,
		dependencies = { "neovim/nvim-lspconfig" },
		config = function()
			local java_home = vim.env.JAVA_HOME

			vim.lsp.config("kotlin_language_server", {
				cmd = {
					vim.fn.expand(
						"~/ghq/github.com/riii111/kotlin-language-server/server/build/install/server/bin/kotlin-language-server"
					),
				},
				cmd_env = {
					JAVA_HOME = java_home,
					JDK_HOME = java_home,
					PATH = (java_home and (java_home .. "/bin:" .. vim.env.PATH)) or vim.env.PATH,
				},
				filetypes = { "kotlin" },
				root_dir = function(bufnr, on_dir)
					local fname = vim.api.nvim_buf_get_name(bufnr)
					-- Multi-module projects need settings.gradle.kts as root to resolve cross-module dependencies
					local root = vim.fs.root(fname, { "settings.gradle.kts", "settings.gradle" })
						or vim.fs.root(fname, { "build.gradle.kts", "build.gradle" })
					if root then
						on_dir(root)
					end
				end,
				init_options = {
					storagePath = vim.fn.stdpath("cache") .. "/kotlin-language-server",
				},
				settings = {
					kotlin = {
						compiler = { jvm = { target = "17" } },
						indexing = {
							enabled = true,
						},
						externalSources = {
							autoConvertToKotlin = false,
							useKlsScheme = true,
						},
					},
				},
			})

			vim.lsp.enable("kotlin_language_server")

			-- Keymaps (IntelliJ-like actions)
			local ok, lsp_actions = pcall(require, "utils.lsp-actions")
			if ok then
				vim.api.nvim_create_autocmd("FileType", {
					pattern = "kotlin",
					callback = function()
						local opts = { buffer = true, silent = true }
						vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
						vim.keymap.set("n", "<D-S-r>", lsp_actions.kotlin_refactor_menu, opts)
						vim.keymap.set("n", "<M-S-r>", lsp_actions.kotlin_refactor_menu, opts)
					end,
				})
			end

			-- Register ktlint sources (once)
			local null_ls_ok, null_ls = pcall(require, "null-ls")
			if null_ls_ok and not vim.g._kotlin_null_ls_registered then
				vim.g._kotlin_null_ls_registered = true
				null_ls.register(null_ls.builtins.formatting.ktlint)
				null_ls.register(null_ls.builtins.diagnostics.ktlint)
			end
		end,
	},
}
