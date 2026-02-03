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

			-- Custom highlight groups for better visibility
			local function setup_octo_highlights()
				-- Editable areas with subtle background
				vim.api.nvim_set_hl(0, "OctoEditable", { bg = "#2d333b" })

				-- Details label (bold and bright)
				vim.api.nvim_set_hl(0, "OctoDetailsLabel", { fg = "#7dcfff", bold = true })
				vim.api.nvim_set_hl(0, "OctoDetailsValue", { fg = "#c0caf5" })

				-- User bubbles
				vim.api.nvim_set_hl(0, "OctoBubble", { fg = "#1a1b26", bg = "#7aa2f7" })

				-- State bubbles (Open/Closed/Merged etc.) - darker bg for better contrast
				vim.api.nvim_set_hl(0, "OctoBubbleGreen", { fg = "#1a1b26", bg = "#73daca" })
				vim.api.nvim_set_hl(0, "OctoStateOpenBubble", { fg = "#1a1b26", bg = "#73daca" })

				-- Timeline/commit history (no bold)
				vim.api.nvim_set_hl(0, "OctoTimelineItemHeading", { fg = "#565f89" })
				vim.api.nvim_set_hl(0, "OctoSymbol", { fg = "#565f89" })

				-- Markdown headings in Octo buffers (purple/blue tones to match theme)
				vim.api.nvim_set_hl(0, "OctoH1", { fg = "#bb9af7", bold = true })
				vim.api.nvim_set_hl(0, "OctoH2", { fg = "#7aa2f7", bold = true })
				vim.api.nvim_set_hl(0, "OctoH3", { fg = "#7dcfff", bold = true })
			end

			setup_octo_highlights()

			-- Apply heading highlights to Octo buffers
			vim.api.nvim_create_autocmd("FileType", {
				pattern = "octo",
				callback = function(ev)
					vim.schedule(function()
						if not vim.api.nvim_buf_is_valid(ev.buf) then
							return
						end

						-- Match markdown headings
						vim.fn.matchadd("OctoH1", "^# .*$")
						vim.fn.matchadd("OctoH2", "^## .*$")
						vim.fn.matchadd("OctoH3", "^### .*$")
					end)
				end,
			})
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
