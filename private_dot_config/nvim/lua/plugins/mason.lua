return {
	-- Mason tool installer
	{
		"mason-org/mason.nvim",
		priority = 100,
		config = function()
			require("mason").setup({
				PATH = "append", -- ensure mason bins are appended to $PATH
			})
		end,
	},

	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "mason-org/mason.nvim" },
		priority = 80,
		opts = {
			ensure_installed = {
				-- LSP servers
				"lua-language-server",
				"gopls",
				"typescript-language-server", -- ts_ls用
				"basedpyright",
				"terraform-ls",

				-- Formatters
				"goimports",
				"ruff",
				"ktlint",
				-- C/C++
				"clangd",
				"clang-format",

				-- Linters
				"golangci-lint",
				"ruff",
				"tflint",
				"ktlint",

				-- Other tools
				"tree-sitter-cli",
			},
			auto_update = false,
			run_on_start = false,
			-- Disable automatic integration that causes conflicts
			integrations = {
				["mason-lspconfig"] = false,
			},
		},
	},
}
