return {
	{
		"folke/noice.nvim",
		event = "VeryLazy",
		dependencies = {
			"MunifTanjim/nui.nvim",
			"rcarriga/nvim-notify",
		},
		opts = {
			lsp = {
				override = {
					["vim.lsp.util.convert_input_to_markdown_lines"] = true,
					["vim.lsp.util.stylize_markdown"] = true,
					["cmp.entry.get_documentation"] = true,
				},
			},
			routes = {
				-- Most notifications to mini view (very minimal)
				{
					filter = {
						event = "msg_show",
						any = {
							{ find = "%d+L, %d+B" },
							{ find = "; after #%d+" },
							{ find = "; before #%d+" },
							{ find = "search hit" },
							{ find = "written" },
							{ find = "yanked" },
							{ find = "more line" },
							{ find = "fewer line" },
							{ find = "lines changed" },
							{ find = "change;" },
							{ find = "changes;" },
							{ find = "substitute" },
							{ find = "already at" },
							{ find = "E486" },
							{ find = "Pattern not found" },
						},
					},
					view = "mini",
				},
				-- Hide very common messages completely
				{
					filter = {
						event = "msg_show",
						any = {
							{ find = "^E486:" },
							{ find = "^E:" },
							{ find = "Already at" },
						},
					},
					opts = { skip = true },
				},
			},
			cmdline = {
				enabled = true,
				view = "cmdline",
			},
			popupmenu = {
				enabled = true,
				backend = "nui",
				kind_icons = {},
			},
			presets = {
				bottom_search = true,
				command_palette = false,
				long_message_to_split = true,
				inc_rename = false,
				lsp_doc_border = true,
			},
			views = {
				notify = {
					backend = "notify",
					fallback = "mini",
				},
				mini = {
					timeout = 1500,
					reverse = true,
					position = { row = -1, col = "100%" },
					win_options = {
						winblend = 50,
					},
				},
			},
		},
		config = function(_, opts)
			local function setup_notify()
				local notify_opts = {
					fps = 30,
					level = 2,
					minimum_width = 50,
					render = "compact",
					stages = "fade_in_slide_out",
					timeout = 5000,
					top_down = false,
				}
				if vim.g.colors_name == "custom-theme-riii111" then
					notify_opts.background_colour = require("custom-theme-riii111").palette().base.bg_medium
				end
				require("notify").setup(notify_opts)
			end

			setup_notify()

			vim.api.nvim_create_autocmd("ColorScheme", {
				callback = setup_notify,
				group = vim.api.nvim_create_augroup("NotifyCustomTheme", { clear = true }),
			})

			require("noice").setup(opts)
		end,
	},
}
