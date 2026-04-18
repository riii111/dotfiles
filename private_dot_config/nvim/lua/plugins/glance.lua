return {
	{
		"dnlhc/glance.nvim",
		cmd = "Glance",
		opts = {
			detached = true,
			border = {
				enable = true,
				top_char = "―",
				bottom_char = "―",
			},
			height = 18,
			theme = {
				enable = true,
				mode = "auto",
			},
			list = {
				position = "right",
				width = 0.33,
			},
			hooks = {},
			folds = {
				fold_closed = "",
				fold_open = "",
				folded = true,
			},
			indent_lines = {
				enable = true,
				icon = "│",
			},
			winbar = {
				enable = true,
			},
		},
	},
}
