return {
	{
		"nvim-telescope/telescope.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{
				"nvim-telescope/telescope-live-grep-args.nvim",
				version = "^1.0.0",
			},
			{
				"nvim-telescope/telescope-fzf-native.nvim",
				build = "make",
			},
		},
		opts = function()
			return {
				defaults = {
					file_ignore_patterns = {
						"node_modules/.*",
						"%.git/.*",
						"target/.*",
						"dist/.*",
						"build/.*",
						"%.lock",
						"vendor/.*",
						"%.min%.js",
						"%.min%.css",
					},
					vimgrep_arguments = {
						"rg",
						"--color=never",
						"--no-heading",
						"--with-filename",
						"--line-number",
						"--column",
						"--smart-case",
						"--trim",
						"--hidden",
						"--fixed-strings",
					},
					mappings = {
						i = {
							["<M-q>"] = function(prompt_bufnr)
								require("telescope.actions").send_to_qflist(prompt_bufnr)
								require("telescope.actions").open_qflist(prompt_bufnr)
							end,
							["<C-k>"] = require("telescope.actions").cycle_history_prev,
							["<C-j>"] = require("telescope.actions").cycle_history_next,
							["<Esc>"] = function()
								vim.cmd("stopinsert")
							end,
						},
						n = {
							["<Esc>"] = require("telescope.actions").close,
						},
					},
					prompt_prefix = "󰼛 ",
					selection_caret = "󰅂 ",
					dynamic_preview_title = true,
					path_display = { "truncate" },
					layout_config = {
						horizontal = {
							prompt_position = "top",
							preview_width = 0.55,
							preview_cutoff = 0,
						},
						width = 0.9,
						height = 0.9,
					},
					sorting_strategy = "ascending",
					winblend = 0,
				},
				pickers = {
					find_files = {
						hidden = true,
					},
				},
				extensions = {
					fzf = {
						fuzzy = true,
						override_generic_sorter = true,
						override_file_sorter = true,
						case_mode = "smart_case",
					},
					live_grep_args = {
						auto_quoting = true,
						prompt_title = "Live Grep [⌥I:in ⌥E:ex ⌥W:word ⌥Q:qf ^jk:hist]",
						mappings = {
							i = {
								["<C-r>"] = require("telescope-live-grep-args.actions").quote_prompt({
									postfix = " --no-fixed-strings ",
								}),
								["<CR>"] = function(prompt_bufnr)
									local action_state = require("telescope.actions.state")
									_G.last_grep_input = action_state.get_current_line()
									require("telescope.actions").select_default(prompt_bufnr)
								end,
								["<Esc>"] = function()
									local action_state = require("telescope.actions.state")
									_G.last_grep_input = action_state.get_current_line()
									vim.cmd("stopinsert")
								end,
								["<M-w>"] = require("telescope-live-grep-args.actions").quote_prompt({
									postfix = " -w ",
								}),
								["<M-i>"] = function()
									local action_state = require("telescope.actions.state")
									local picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
									local current = action_state.get_current_line()
									picker:set_prompt('-g "**" ' .. current)
									vim.defer_fn(function()
										vim.api.nvim_feedkeys(
											vim.api.nvim_replace_termcodes(
												"<Home><Right><Right><Right><Right>",
												true,
												false,
												true
											),
											"n",
											false
										)
									end, 10)
								end,
								["<M-e>"] = function()
									local action_state = require("telescope.actions.state")
									local picker = action_state.get_current_picker(vim.api.nvim_get_current_buf())
									local current = action_state.get_current_line()
									picker:set_prompt('-g "!**" ' .. current)
									vim.defer_fn(function()
										vim.api.nvim_feedkeys(
											vim.api.nvim_replace_termcodes(
												"<Home><Right><Right><Right><Right><Right>",
												true,
												false,
												true
											),
											"n",
											false
										)
									end, 10)
								end,
							},
							n = {
								["<Esc>"] = function(prompt_bufnr)
									local action_state = require("telescope.actions.state")
									_G.last_grep_input = action_state.get_current_line()
									require("telescope.actions").close(prompt_bufnr)
								end,
							},
						},
					},
				},
			}
		end,
		config = function(_, opts)
			local telescope = require("telescope")
			telescope.setup(opts)
			telescope.load_extension("fzf")
			telescope.load_extension("live_grep_args")
		end,
	},
}
