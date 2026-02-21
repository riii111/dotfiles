return {
	{
		"skanehira/github-actions.nvim",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-telescope/telescope.nvim",
		},
		cmd = {
			"GithubActionsHistory",
			"GithubActionsHistoryByPR",
			"GithubActionsDispatch",
			"GithubActionsWatch",
		},
		keys = {
			{ "<leader>gA", "<cmd>GithubActionsHistory<cr>", desc = "Actions history" },
			{ "<leader>gB", "<cmd>GithubActionsHistoryByPR<cr>", desc = "Actions history by branch/PR" },
			{ "<leader>gX", "<cmd>GithubActionsDispatch<cr>", desc = "Actions dispatch" },
			{ "<leader>gW", "<cmd>GithubActionsWatch<cr>", desc = "Actions watch" },
		},
		opts = {
			history = {
				highlight_colors = {
					success = { fg = "#a6e3a1", bold = true },
					failure = { fg = "#f38ba8", bold = true },
					cancelled = { fg = "#6c7086", bold = true },
					running = { fg = "#f9e2af", bold = true },
					queued = { fg = "#cba6f7", bold = true },
				},
				buffer = {
					history = {
						open_mode = "tab",
						window_options = {
							wrap = true,
							number = false,
							cursorline = true,
						},
					},
					logs = {
						open_mode = "vsplit",
						window_options = {
							wrap = false,
							number = false,
						},
					},
				},
			},
		},
	},
}
