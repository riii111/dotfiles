return {
	{
		"pwntester/octo.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"nvim-telescope/telescope.nvim",
			"nvim-tree/nvim-web-devicons",
		},
		cmd = "Octo",
		config = function(_, opts)
			require("octo").setup(opts)

			-- Catppuccin Mocha inspired highlights for Octo
			local function setup_octo_highlights()
				-- Catppuccin Mocha palette
				local mocha = {
					rosewater = "#f5e0dc",
					flamingo = "#f2cdcd",
					pink = "#f5c2e7",
					mauve = "#cba6f7",
					red = "#f38ba8",
					maroon = "#eba0ac",
					peach = "#fab387",
					yellow = "#f9e2af",
					green = "#a6e3a1",
					teal = "#94e2d5",
					sky = "#89dceb",
					sapphire = "#74c7ec",
					blue = "#89b4fa",
					lavender = "#b4befe",
					text = "#cdd6f4",
					subtext1 = "#bac2de",
					subtext0 = "#a6adc8",
					overlay2 = "#9399b2",
					overlay1 = "#7f849c",
					overlay0 = "#6c7086",
					surface2 = "#585b70",
					surface1 = "#45475a",
					surface0 = "#313244",
					base = "#1e1e2e",
					mantle = "#181825",
					crust = "#11111b",
				}

				-- Editable areas
				vim.api.nvim_set_hl(0, "OctoEditable", { bg = mocha.surface0 })

				-- Details label
				vim.api.nvim_set_hl(0, "OctoDetailsLabel", { fg = mocha.sapphire, bold = true })
				vim.api.nvim_set_hl(0, "OctoDetailsValue", { fg = mocha.text })

				-- User bubbles
				vim.api.nvim_set_hl(0, "OctoBubble", { fg = mocha.crust, bg = mocha.blue })

				-- State bubbles
				vim.api.nvim_set_hl(0, "OctoBubbleGreen", { fg = mocha.crust, bg = mocha.green })
				vim.api.nvim_set_hl(0, "OctoStateOpenBubble", { fg = mocha.crust, bg = mocha.green })

				-- Timeline/commit history
				vim.api.nvim_set_hl(0, "OctoTimelineItemHeading", { fg = mocha.overlay1 })
				vim.api.nvim_set_hl(0, "OctoSymbol", { fg = mocha.overlay1 })

				-- Headings
				vim.api.nvim_set_hl(0, "@markup.heading.1.markdown", { fg = mocha.text, bold = true })
				vim.api.nvim_set_hl(0, "@markup.heading.2.markdown", { fg = mocha.text, bold = true })
				vim.api.nvim_set_hl(0, "@markup.heading.3.markdown", { fg = mocha.subtext1, bold = true })
				vim.api.nvim_set_hl(0, "@markup.heading.4.markdown", { fg = mocha.subtext1, bold = true })
				vim.api.nvim_set_hl(0, "@markup.heading.5.markdown", { fg = mocha.subtext0, bold = true })
				vim.api.nvim_set_hl(0, "@markup.heading.6.markdown", { fg = mocha.subtext0, bold = true })

				-- Heading backgrounds for render-markdown
				vim.api.nvim_set_hl(0, "RenderMarkdownH1Bg", { bg = mocha.surface0 })
				vim.api.nvim_set_hl(0, "RenderMarkdownH2Bg", { bg = "#292938" })
				vim.api.nvim_set_hl(0, "RenderMarkdownH3Bg", { bg = "#242434" })
				vim.api.nvim_set_hl(0, "RenderMarkdownH4Bg", { bg = "#212130" })
				vim.api.nvim_set_hl(0, "RenderMarkdownH5Bg", { bg = mocha.mantle })
				vim.api.nvim_set_hl(0, "RenderMarkdownH6Bg", { bg = mocha.crust })

				-- Buffer background (slightly darker than mantle)
				vim.api.nvim_set_hl(0, "OctoNormal", { bg = "NONE" })
				vim.api.nvim_set_hl(0, "OctoNormalNC", { bg = "NONE" })
			end

			setup_octo_highlights()

			-- Apply darker background to Octo buffers only
			vim.api.nvim_create_autocmd("FileType", {
				pattern = "octo",
				callback = function()
					vim.opt_local.winhighlight = "Normal:OctoNormal,NormalNC:OctoNormalNC"
				end,
			})

			-- Apply heading highlights and fold <details> tags in Octo buffers
			vim.api.nvim_create_autocmd("FileType", {
				pattern = "octo",
				callback = function(ev)
					vim.schedule(function()
						if not vim.api.nvim_buf_is_valid(ev.buf) then
							return
						end

						-- Fold <details> tags by default
						vim.wo.foldmethod = "expr"
						vim.wo.foldexpr = "v:lua.OctoDetailsFold(v:lnum)"
						vim.wo.foldlevel = 0
						vim.wo.foldenable = true
					end)
				end,
			})

			-- Fold expression for <details> tags
			_G.OctoDetailsFold = function(lnum)
				local line = vim.fn.getline(lnum)
				if line:match("^<details") then
					return ">1"
				elseif line:match("^</details>") then
					return "<1"
				else
					return "="
				end
			end
		end,
		keys = {
			{ "<leader>gi", "<cmd>Octo issue list<cr>", desc = "List issues" },
			{ "<leader>gI", "<cmd>Octo issue search<cr>", desc = "Search issues" },
			{ "<leader>gp", "<cmd>Octo pr list<cr>", desc = "List PRs" },
			{ "<leader>gP", "<cmd>Octo pr search<cr>", desc = "Search PRs" },
			{ "<leader>gr", "<cmd>Octo repo list<cr>", desc = "List repos" },
		},
		opts = {
			picker = "telescope",
			enable_builtin = true,
			default_to_projects_v2 = true,
			suppress_missing_scope = {
				projects_v2 = true,
			},
			-- SSH host alias mapping (for multiple GitHub accounts)
			ssh_aliases = {
				["github.com-riii111"] = "github.com",
			},
			-- Simpler colors inspired by gh pr view
			colors = {
				white = "#c0caf5",
				grey = "#565f89",
				black = "#1a1b26",
				red = "#f7768e",
				dark_red = "#db4b4b",
				green = "#9ece6a",
				dark_green = "#73daca",
				yellow = "#e0af68",
				dark_yellow = "#ff9e64",
				blue = "#7aa2f7",
				dark_blue = "#7dcfff",
				purple = "#bb9af7",
			},
			ui = {
				use_signcolumn = false,
				use_signstatus = true,
			},
			mappings_disable_default = false,
			mappings = {
				issue = {
					close_issue = { lhs = "<leader>ic", desc = "Close issue" },
					reopen_issue = { lhs = "<leader>io", desc = "Reopen issue" },
					list_issues = { lhs = "<leader>il", desc = "List issues" },
					reload = { lhs = "<C-r>", desc = "Reload" },
					open_in_browser = { lhs = "<C-b>", desc = "Open in browser" },
					copy_url = { lhs = "<C-y>", desc = "Copy URL" },
					add_assignee = { lhs = "<leader>aa", desc = "Add assignee" },
					remove_assignee = { lhs = "<leader>ad", desc = "Remove assignee" },
					add_label = { lhs = "<leader>la", desc = "Add label" },
					remove_label = { lhs = "<leader>ld", desc = "Remove label" },
					goto_issue = { lhs = "<leader>gi", desc = "Go to issue" },
					add_comment = { lhs = "<leader>ca", desc = "Add comment" },
					delete_comment = { lhs = "<leader>cd", desc = "Delete comment" },
					next_comment = { lhs = "]c", desc = "Next comment" },
					prev_comment = { lhs = "[c", desc = "Prev comment" },
					react_hooray = { lhs = "<leader>rp", desc = "React 🎉" },
					react_heart = { lhs = "<leader>rh", desc = "React ❤️" },
					react_eyes = { lhs = "<leader>re", desc = "React 👀" },
					react_thumbs_up = { lhs = "<leader>r+", desc = "React 👍" },
					react_thumbs_down = { lhs = "<leader>r-", desc = "React 👎" },
					react_rocket = { lhs = "<leader>rr", desc = "React 🚀" },
					react_laugh = { lhs = "<leader>rl", desc = "React 😄" },
					react_confused = { lhs = "<leader>rc", desc = "React 😕" },
				},
				pull_request = {
					checkout_pr = { lhs = "<leader>po", desc = "Checkout PR" },
					merge_pr = { lhs = "<leader>pm", desc = "Merge PR" },
					squash_and_merge_pr = { lhs = "<leader>psm", desc = "Squash and merge" },
					rebase_and_merge_pr = { lhs = "<leader>prm", desc = "Rebase and merge" },
					list_commits = { lhs = "<leader>pc", desc = "List commits" },
					list_changed_files = { lhs = "<leader>pf", desc = "List changed files" },
					show_pr_diff = { lhs = "<leader>pd", desc = "Show PR diff" },
					add_reviewer = { lhs = "<leader>va", desc = "Add reviewer" },
					remove_reviewer = { lhs = "<leader>vd", desc = "Remove reviewer" },
					close_issue = { lhs = "<leader>ic", desc = "Close PR" },
					reopen_issue = { lhs = "<leader>io", desc = "Reopen PR" },
					reload = { lhs = "<C-r>", desc = "Reload" },
					open_in_browser = { lhs = "<C-b>", desc = "Open in browser" },
					copy_url = { lhs = "<C-y>", desc = "Copy URL" },
					goto_file = { lhs = "gf", desc = "Go to file" },
					add_assignee = { lhs = "<leader>aa", desc = "Add assignee" },
					remove_assignee = { lhs = "<leader>ad", desc = "Remove assignee" },
					add_label = { lhs = "<leader>la", desc = "Add label" },
					remove_label = { lhs = "<leader>ld", desc = "Remove label" },
					goto_issue = { lhs = "<leader>gi", desc = "Go to issue" },
					add_comment = { lhs = "<leader>ca", desc = "Add comment" },
					delete_comment = { lhs = "<leader>cd", desc = "Delete comment" },
					next_comment = { lhs = "]c", desc = "Next comment" },
					prev_comment = { lhs = "[c", desc = "Prev comment" },
					react_hooray = { lhs = "<leader>rp", desc = "React 🎉" },
					react_heart = { lhs = "<leader>rh", desc = "React ❤️" },
					react_eyes = { lhs = "<leader>re", desc = "React 👀" },
					react_thumbs_up = { lhs = "<leader>r+", desc = "React 👍" },
					react_thumbs_down = { lhs = "<leader>r-", desc = "React 👎" },
					react_rocket = { lhs = "<leader>rr", desc = "React 🚀" },
					react_laugh = { lhs = "<leader>rl", desc = "React 😄" },
					react_confused = { lhs = "<leader>rc", desc = "React 😕" },
				},
				review_thread = {
					goto_issue = { lhs = "<leader>gi", desc = "Go to issue" },
					add_comment = { lhs = "<leader>ca", desc = "Add comment" },
					add_suggestion = { lhs = "<leader>sa", desc = "Add suggestion" },
					delete_comment = { lhs = "<leader>cd", desc = "Delete comment" },
					next_comment = { lhs = "]c", desc = "Next comment" },
					prev_comment = { lhs = "[c", desc = "Prev comment" },
					select_next_entry = { lhs = "]q", desc = "Next changed file" },
					select_prev_entry = { lhs = "[q", desc = "Prev changed file" },
					select_first_entry = { lhs = "[Q", desc = "First changed file" },
					select_last_entry = { lhs = "]Q", desc = "Last changed file" },
					close_review_tab = { lhs = "<C-c>", desc = "Close review tab" },
					react_hooray = { lhs = "<leader>rp", desc = "React 🎉" },
					react_heart = { lhs = "<leader>rh", desc = "React ❤️" },
					react_eyes = { lhs = "<leader>re", desc = "React 👀" },
					react_thumbs_up = { lhs = "<leader>r+", desc = "React 👍" },
					react_thumbs_down = { lhs = "<leader>r-", desc = "React 👎" },
					react_rocket = { lhs = "<leader>rr", desc = "React 🚀" },
					react_laugh = { lhs = "<leader>rl", desc = "React 😄" },
					react_confused = { lhs = "<leader>rc", desc = "React 😕" },
				},
				submit_win = {
					approve_review = { lhs = "<C-a>", desc = "Approve review" },
					comment_review = { lhs = "<C-m>", desc = "Comment review" },
					request_changes = { lhs = "<C-r>", desc = "Request changes" },
					close_review_tab = { lhs = "<C-c>", desc = "Close review tab" },
				},
				review_diff = {
					submit_review = { lhs = "<leader>vs", desc = "Submit review" },
					discard_review = { lhs = "<leader>vd", desc = "Discard review" },
					add_review_comment = { lhs = "<leader>ca", desc = "Add review comment" },
					add_review_suggestion = { lhs = "<leader>sa", desc = "Add suggestion" },
					focus_files = { lhs = "<leader>e", desc = "Focus changed files" },
					toggle_files = { lhs = "<leader>b", desc = "Toggle changed files" },
					next_thread = { lhs = "]t", desc = "Next thread" },
					prev_thread = { lhs = "[t", desc = "Prev thread" },
					select_next_entry = { lhs = "]q", desc = "Next changed file" },
					select_prev_entry = { lhs = "[q", desc = "Prev changed file" },
					select_first_entry = { lhs = "[Q", desc = "First changed file" },
					select_last_entry = { lhs = "]Q", desc = "Last changed file" },
					close_review_tab = { lhs = "<C-c>", desc = "Close review tab" },
					toggle_viewed = { lhs = "<leader>tv", desc = "Toggle viewed" },
					goto_file = { lhs = "gf", desc = "Go to file" },
				},
				file_panel = {
					submit_review = { lhs = "<leader>vs", desc = "Submit review" },
					discard_review = { lhs = "<leader>vd", desc = "Discard review" },
					next_entry = { lhs = "j", desc = "Next entry" },
					prev_entry = { lhs = "k", desc = "Prev entry" },
					select_entry = { lhs = "<cr>", desc = "Select entry" },
					refresh_files = { lhs = "R", desc = "Refresh files" },
					focus_files = { lhs = "<leader>e", desc = "Focus changed files" },
					toggle_files = { lhs = "<leader>b", desc = "Toggle changed files" },
					select_next_entry = { lhs = "]q", desc = "Next changed file" },
					select_prev_entry = { lhs = "[q", desc = "Prev changed file" },
					select_first_entry = { lhs = "[Q", desc = "First changed file" },
					select_last_entry = { lhs = "]Q", desc = "Last changed file" },
					close_review_tab = { lhs = "<C-c>", desc = "Close review tab" },
					toggle_viewed = { lhs = "<leader>tv", desc = "Toggle viewed" },
				},
			},
		},
	},
}
