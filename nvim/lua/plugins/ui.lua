local colors = require("config.colors")

return {

	-- Telescope fuzzy finder
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
					},
					prompt_prefix = "󰼛 ",
					selection_caret = "󰅂 ",
					layout_config = {
						horizontal = {
							prompt_position = "top",
							preview_width = 0.6,
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
						default_text = "--fixed-strings ",
						mappings = {
							i = {
								["<C-k>"] = require("telescope-live-grep-args.actions").quote_prompt(),
								["<C-i>"] = require("telescope-live-grep-args.actions").quote_prompt({
									postfix = " --iglob ",
								}),
								["<C-r>"] = require("telescope-live-grep-args.actions").quote_prompt({
									postfix = " --no-fixed-strings ",
								}),
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


	-- Bufferline (crisidev style)
	{
		"akinsho/bufferline.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		version = "*",
		config = function()
			require("bufferline").setup({
				options = {
					mode = "buffers",
					separator_style = "slant",
					always_show_bufferline = true,
					show_buffer_close_icons = false,
					show_close_icon = false,
					show_tab_indicators = true,
					diagnostics = "nvim_lsp",
					diagnostics_update_in_insert = false,
					diagnostics_indicator = function(count, level)
						local icon = "⚠"
						if level:match("error") then
							icon = "󰅙"
						elseif level:match("warn") then
							icon = "⚠"
						elseif level:match("info") then
							icon = "󰋽"
						elseif level:match("hint") then
							icon = "󰌶"
						end
						return " " .. icon .. count
					end,
					sort_by = "insert_after_current",
					groups = {
						options = {
							toggle_hidden_on_enter = true,
						},
						items = {
							{
								name = "docs",
								highlight = { fg = colors.languages.docs },
								priority = 2,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.md$")
											or buf.name:match("README")
											or buf.name:match("%.rst$")
								end,
							},
							{
								name = "rs",
								highlight = { fg = colors.languages.rust },
								priority = 3,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.rs$")
								end,
							},
							{
								name = "lua",
								highlight = { fg = colors.languages.lua },
								priority = 4,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.lua$")
								end,
							},
							{
								name = "go",
								highlight = { fg = colors.languages.go },
								priority = 5,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.go$")
								end,
							},
							{
								name = "c",
								highlight = { fg = colors.languages.c },
								priority = 5,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.c$")
								end,
							},
							{
								name = "cpp",
								highlight = { fg = colors.languages.cpp },
								priority = 6,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.cpp$")
								end,
							},
							{
								name = "tsx",
								highlight = { fg = colors.languages.tsx },
								priority = 6,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.tsx$")
								end,
							},
							{
								name = "ts",
								highlight = { fg = colors.languages.typescript },
								priority = 7,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.ts$")
								end,
							},
							{
								name = "jsx",
								highlight = { fg = colors.languages.tsx },
								priority = 8,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.jsx$")
								end,
							},
							{
								name = "js",
								highlight = { fg = colors.languages.javascript },
								priority = 9,
								auto_close = true,
								matcher = function(buf)
									return buf.name:match("%.js$")
								end,
							},
						},
					},
					highlights = {
						fill = {
							bg = colors.bufferline.fill,
						},
						background = {
							fg = colors.bufferline.fg,
							bg = colors.bufferline.background,
						},
						buffer = {
							fg = colors.bufferline.fg,
							bg = colors.bufferline.background,
						},
						buffer_selected = {
							fg = colors.bufferline.fg_selected,
							bg = colors.bufferline.buffer_selected,
							bold = true,
						},
						buffer_visible = {
							fg = colors.bufferline.fg,
							bg = colors.bufferline.background,
						},
						tab = {
							fg = colors.bufferline.fg,
							bg = colors.bufferline.background,
						},
						tab_selected = {
							fg = colors.bufferline.fg_selected,
							bg = colors.bufferline.tab_selected,
							bold = true,
						},
						tab_close = {
							fg = colors.bufferline.fg,
							bg = colors.bufferline.background,
						},
						separator = {
							fg = colors.bufferline.background,
							bg = colors.bufferline.background,
						},
						separator_selected = {
							fg = colors.bufferline.buffer_selected,
							bg = colors.bufferline.buffer_selected,
						},
						separator_visible = {
							fg = colors.bufferline.background,
							bg = colors.bufferline.background,
						},
						indicator_selected = {
							fg = colors.bufferline.buffer_selected,
							bg = colors.bufferline.buffer_selected,
						},
						modified = {
							fg = colors.semantic.warning,
							bg = colors.bufferline.background,
						},
						modified_selected = {
							fg = colors.semantic.warning,
							bg = colors.bufferline.buffer_selected,
						},
						modified_visible = {
							fg = colors.semantic.warning,
							bg = colors.bufferline.background,
						},
					},
					offsets = {
						{
							filetype = "neo-tree",
							text = "File Explorer",
							highlight = "Directory",
							text_align = "left",
						},
					},
				},
			})
		end,
	},

	-- Incline (file path display)
	{
		"b0o/incline.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		event = "BufReadPre",
		priority = 1200,
		config = function()
			require("incline").setup({
				highlight = {
					groups = {
						InclineNormal = { guibg = colors.base.bg_light, guifg = colors.base.fg_alt },
						InclineNormalNC = { guifg = colors.base.fg_muted, guibg = colors.base.bg_accent_alt },
					},
				},
				window = { margin = { vertical = 0, horizontal = 1 } },
				hide = {
					cursorline = false,
				},
				render = function(props)
					local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
					if vim.bo[props.buf].modified then
						filename = "[+] " .. filename
					end

					local icon, color = require("nvim-web-devicons").get_icon_color(filename)

					-- Simple path display without complex segments
					local path = vim.api.nvim_buf_get_name(props.buf)
					local segments = {}

					if path ~= "" then
						local parts = vim.split(path, "/")
						-- Show only parent directory and filename
						if #parts > 1 then
							local parent = parts[#parts - 1]
							table.insert(segments, { parent, guifg = colors.base.fg_muted })
							table.insert(segments, { " > ", guifg = colors.base.fg_muted })
						end
					end

					-- File icon and name
					table.insert(segments, { (icon and icon .. " " or ""), guifg = color or colors.base.white })
					table.insert(segments, { filename, gui = "bold" })

					return segments
				end,
			})
		end,
	},

	-- Indent guides
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = "VeryLazy",
		config = function()
			require("ibl").setup({
				indent = {
					highlight = { "IndentBlanklineChar" },
					char = "│",
				},
				scope = {
					highlight = { "IndentBlanklineContextChar" },
					enabled = true,
				},
			})
		end,
	},

	-- Git signs
	{
		"lewis6991/gitsigns.nvim",
		opts = {},
	},

	-- Terminal
	{
		"akinsho/toggleterm.nvim",
		version = "*",
		opts = function()
			return {
				size = function(term)
					if term.direction == "horizontal" then
						return 15
					elseif term.direction == "vertical" then
						return vim.o.columns * 0.4
					end
				end,
				open_mapping = [[<c-\>]],
				hide_numbers = true,
				shade_terminals = false,
				start_in_insert = true,
				insert_mappings = true,
				terminal_mappings = true,
				persist_size = true,
				persist_mode = true,
				direction = "horizontal",
				close_on_exit = true,
				shell = vim.o.shell,
				auto_scroll = true,
				highlights = {
					Normal = { guibg = "NONE" },
					NormalFloat = { guibg = "NONE" },
					FloatBorder = { guifg = colors.base.accent, guibg = colors.base.bg },
				},
			}
		end,
		config = function(_, opts)
			require("toggleterm").setup(opts)

			local Terminal = require("toggleterm.terminal").Terminal

			-- Horizontal terminal
			local horizontal_term = Terminal:new({
				direction = "horizontal",
				size = 15,
			})

			-- Vertical terminal
			local vertical_term = Terminal:new({
				direction = "vertical",
				size = function()
					return math.floor(vim.o.columns * 0.4)
				end,
			})

			-- Float terminal (default)
			local float_term = Terminal:new({
				direction = "float",
			})

			-- Key mappings for different layouts
			vim.keymap.set("n", "<Leader>tf", function()
				float_term:toggle()
			end, { desc = "Float terminal" })
			vim.keymap.set("n", "<Leader>th", function()
				horizontal_term:toggle()
			end, { desc = "Horizontal terminal" })
			vim.keymap.set("n", "<Leader>tv", function()
				vertical_term:toggle()
			end, { desc = "Vertical terminal" })

			-- Terminal mode mappings
			function _G.set_terminal_keymaps()
				local opts = { buffer = 0 }
				vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], opts)
				vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], opts)
				vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], opts)
				vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], opts)
				vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], opts)
				vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], opts)
			end

			vim.cmd("autocmd! TermOpen term://* lua set_terminal_keymaps()")
		end,
	},


	-- Glance preview
	{
		"dnlhc/glance.nvim",
		opts = {},
	},

	-- Markview for markdown
	{
		"OXY2DEV/markview.nvim",
		event = { "BufReadPre *.md", "BufNewFile *.md" },
		config = true,
		opts = {},
	},


	-- Search highlighting
	{
		"kevinhwang91/nvim-hlslens",
		event = "VeryLazy",
		config = function()
			require("hlslens").setup({
				calm_down = true,
				nearest_only = true,
				nearest_float_when = "always",
				float_shadow_blend = 0,
				virt_priority = 100,
				override_lens = function(render, posList, nearest, idx, relIdx)
					local sfw = vim.v.searchforward == 1
					local indicator, text, chunks
					local absRelIdx = math.abs(relIdx)

					if absRelIdx > 1 then
						indicator = ("%d%s"):format(absRelIdx, sfw ~= (relIdx > 1) and "▲" or "▼")
					elseif absRelIdx == 1 then
						indicator = sfw ~= (relIdx == 1) and "▲" or "▼"
					else
						indicator = ""
					end

					local lnum, col = unpack(posList[idx])
					if nearest then
						local cnt = #posList
						text = indicator ~= "" and ("[%s %d/%d]"):format(indicator, idx, cnt)
								or ("[%d/%d]"):format(idx, cnt)
						chunks = { { " " }, { text, "HlSearchLensNear" } }
					else
						text = ("[%s %d]"):format(indicator, idx)
						chunks = { { " " }, { text, "HlSearchLens" } }
					end

					render.setVirt(0, lnum - 1, col - 1, chunks, nearest)
				end,
			})

			local kopts = { noremap = true, silent = true }

			vim.keymap.set(
				"n",
				"n",
				[[<Cmd>execute('normal! ' . v:count1 . 'n')<CR><Cmd>lua require('hlslens').start()<CR>]],
				kopts
			)
			vim.keymap.set(
				"n",
				"N",
				[[<Cmd>execute('normal! ' . v:count1 . 'N')<CR><Cmd>lua require('hlslens').start()<CR>]],
				kopts
			)
			vim.keymap.set("n", "*", [[*<Cmd>lua require('hlslens').start()<CR>]], kopts)
			vim.keymap.set("n", "#", [[#<Cmd>lua require('hlslens').start()<CR>]], kopts)
			vim.keymap.set("n", "g*", [[g*<Cmd>lua require('hlslens').start()<CR>]], kopts)
			vim.keymap.set("n", "g#", [[g#<Cmd>lua require('hlslens').start()<CR>]], kopts)

			vim.keymap.set("n", "<Esc>", "<Cmd>noh<CR><Cmd>lua require('hlslens').stop()<CR>", kopts)
		end,
	},

	-- Line moving
	{
		"echasnovski/mini.move",
		version = "*",
		event = "VeryLazy",
		config = function()
			require("mini.move").setup()
			vim.keymap.set("v", "<M-Down>", function()
				require("mini.move").move_selection("down")
			end)
			vim.keymap.set("v", "<M-Up>", function()
				require("mini.move").move_selection("up")
			end)
			vim.keymap.set("n", "<M-Down>", function()
				require("mini.move").move_line("down")
			end)
			vim.keymap.set("n", "<M-Up>", function()
				require("mini.move").move_line("up")
			end)
		end,
	},

	-- Diffview for IntelliJ-like conflict resolution
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
		config = function()
			require("diffview").setup({
				diff_binaries = false,
				enhanced_diff_hl = true,
				git_cmd = { "git" },
				hg_cmd = { "hg" },
				diff_algorithm = "histogram",
				use_icons = true,
				show_help_hints = true,
				watch_index = true,
				icons = {
					folder_closed = "",
					folder_open = "",
				},
				signs = {
					fold_closed = "",
					fold_open = "",
					done = "✓",
				},
				view = {
					default = {
						layout = "diff2_horizontal",
						winbar_info = false,
					},
					merge_tool = {
						layout = "diff3_horizontal",
						disable_diagnostics = true,
						winbar_info = true,
					},
					file_history = {
						layout = "diff2_horizontal",
						winbar_info = false,
					},
				},
				file_panel = {
					listing_style = "tree",
					tree_options = {
						flatten_dirs = true,
						folder_statuses = "only_folded",
					},
					win_config = {
						position = "left",
						width = 35,
						win_opts = {},
					},
				},
				file_history_panel = {
					log_options = {
						git = {
							single_file = {
								diff_merges = "combined",
							},
							multi_file = {
								diff_merges = "first-parent",
							},
						},
						hg = {
							single_file = {},
							multi_file = {},
						},
					},
					win_config = {
						position = "bottom",
						height = 16,
						win_opts = {},
					},
				},
				commit_log_panel = {
					win_config = {},
				},
				default_args = {
					DiffviewOpen = {},
					DiffviewFileHistory = {},
				},
				hooks = {},
				keymaps = {
					disable_defaults = false,
					view = {
						{
							"n",
							"<tab>",
							"<cmd>lua require('diffview.actions').select_next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"<s-tab>",
							"<cmd>lua require('diffview.actions').select_prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"gf",
							"<cmd>lua require('diffview.actions').goto_file_edit()<CR>",
							{ desc = "Open file in current window" },
						},
						{
							"n",
							"<C-w><C-f>",
							"<cmd>lua require('diffview.actions').goto_file_split()<CR>",
							{ desc = "Open file in split" },
						},
						{
							"n",
							"<C-w>gf",
							"<cmd>lua require('diffview.actions').goto_file_tab()<CR>",
							{ desc = "Open file in new tab" },
						},
						{
							"n",
							"<leader>df",
							"<cmd>lua require('diffview.actions').focus_files()<CR>",
							{ desc = "Focus file panel" },
						},
						{
							"n",
							"<leader>b",
							"<cmd>lua require('diffview.actions').toggle_files()<CR>",
							{ desc = "Toggle file panel" },
						},
						{
							"n",
							"g<C-x>",
							"<cmd>lua require('diffview.actions').cycle_layout()<CR>",
							{ desc = "Cycle layout" },
						},
						{
							"n",
							"[x",
							"<cmd>lua require('diffview.actions').prev_conflict()<CR>",
							{ desc = "Previous conflict" },
						},
						{
							"n",
							"]x",
							"<cmd>lua require('diffview.actions').next_conflict()<CR>",
							{ desc = "Next conflict" },
						},
						{
							"n",
							"<leader>co",
							"<cmd>lua require('diffview.actions').conflict_choose('ours')<CR>",
							{ desc = "Choose OURS" },
						},
						{
							"n",
							"<leader>ct",
							"<cmd>lua require('diffview.actions').conflict_choose('theirs')<CR>",
							{ desc = "Choose THEIRS" },
						},
						{
							"n",
							"<leader>cb",
							"<cmd>lua require('diffview.actions').conflict_choose('base')<CR>",
							{ desc = "Choose BASE" },
						},
						{
							"n",
							"<leader>ca",
							"<cmd>lua require('diffview.actions').conflict_choose('all')<CR>",
							{ desc = "Choose ALL" },
						},
						{
							"n",
							"dx",
							"<cmd>lua require('diffview.actions').conflict_choose('none')<CR>",
							{ desc = "Delete conflict" },
						},
						{
							"n",
							"<leader>cO",
							"<cmd>lua require('diffview.actions').conflict_choose_all('ours')<CR>",
							{ desc = "Choose all OURS" },
						},
						{
							"n",
							"<leader>cT",
							"<cmd>lua require('diffview.actions').conflict_choose_all('theirs')<CR>",
							{ desc = "Choose all THEIRS" },
						},
						{
							"n",
							"<leader>cB",
							"<cmd>lua require('diffview.actions').conflict_choose_all('base')<CR>",
							{ desc = "Choose all BASE" },
						},
						{
							"n",
							"<leader>cA",
							"<cmd>lua require('diffview.actions').conflict_choose_all('all')<CR>",
							{ desc = "Choose all ALL" },
						},
						{
							"n",
							"dX",
							"<cmd>lua require('diffview.actions').conflict_choose_all('none')<CR>",
							{ desc = "Delete all conflicts" },
						},
					},
					diff_view = {
						{
							"n",
							"<tab>",
							"<cmd>lua require('diffview.actions').select_next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"<s-tab>",
							"<cmd>lua require('diffview.actions').select_prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"gf",
							"<cmd>lua require('diffview.actions').goto_file_edit()<CR>",
							{ desc = "Open file in current window" },
						},
						{
							"n",
							"<C-w><C-f>",
							"<cmd>lua require('diffview.actions').goto_file_split()<CR>",
							{ desc = "Open file in split" },
						},
						{
							"n",
							"<C-w>gf",
							"<cmd>lua require('diffview.actions').goto_file_tab()<CR>",
							{ desc = "Open file in new tab" },
						},
						{
							"n",
							"<leader>df",
							"<cmd>lua require('diffview.actions').focus_files()<CR>",
							{ desc = "Focus file panel" },
						},
						{
							"n",
							"<leader>b",
							"<cmd>lua require('diffview.actions').toggle_files()<CR>",
							{ desc = "Toggle file panel" },
						},
						{
							"n",
							"g<C-x>",
							"<cmd>lua require('diffview.actions').cycle_layout()<CR>",
							{ desc = "Cycle layout" },
						},
						{
							"n",
							"[x",
							"<cmd>lua require('diffview.actions').prev_conflict()<CR>",
							{ desc = "Previous conflict" },
						},
						{
							"n",
							"]x",
							"<cmd>lua require('diffview.actions').next_conflict()<CR>",
							{ desc = "Next conflict" },
						},
						{
							"n",
							"<leader>co",
							"<cmd>lua require('diffview.actions').conflict_choose('ours')<CR>",
							{ desc = "Choose OURS" },
						},
						{
							"n",
							"<leader>ct",
							"<cmd>lua require('diffview.actions').conflict_choose('theirs')<CR>",
							{ desc = "Choose THEIRS" },
						},
						{
							"n",
							"<leader>cb",
							"<cmd>lua require('diffview.actions').conflict_choose('base')<CR>",
							{ desc = "Choose BASE" },
						},
						{
							"n",
							"<leader>ca",
							"<cmd>lua require('diffview.actions').conflict_choose('all')<CR>",
							{ desc = "Choose ALL" },
						},
						{
							"n",
							"dx",
							"<cmd>lua require('diffview.actions').conflict_choose('none')<CR>",
							{ desc = "Delete conflict" },
						},
						{
							"n",
							"<leader>cO",
							"<cmd>lua require('diffview.actions').conflict_choose_all('ours')<CR>",
							{ desc = "Choose all OURS" },
						},
						{
							"n",
							"<leader>cT",
							"<cmd>lua require('diffview.actions').conflict_choose_all('theirs')<CR>",
							{ desc = "Choose all THEIRS" },
						},
						{
							"n",
							"<leader>cB",
							"<cmd>lua require('diffview.actions').conflict_choose_all('base')<CR>",
							{ desc = "Choose all BASE" },
						},
						{
							"n",
							"<leader>cA",
							"<cmd>lua require('diffview.actions').conflict_choose_all('all')<CR>",
							{ desc = "Choose all ALL" },
						},
						{
							"n",
							"dX",
							"<cmd>lua require('diffview.actions').conflict_choose_all('none')<CR>",
							{ desc = "Delete all conflicts" },
						},
					},
					file_panel = {
						{
							"n",
							"j",
							"<cmd>lua require('diffview.actions').next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"<down>",
							"<cmd>lua require('diffview.actions').next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"k",
							"<cmd>lua require('diffview.actions').prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"<up>",
							"<cmd>lua require('diffview.actions').prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"<cr>",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"o",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"l",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"<2-LeftMouse>",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"-",
							"<cmd>lua require('diffview.actions').toggle_stage_entry()<CR>",
							{ desc = "Stage/unstage" },
						},
						{
							"n",
							"s",
							"<cmd>lua require('diffview.actions').toggle_stage_entry()<CR>",
							{ desc = "Stage/unstage" },
						},
						{
							"n",
							"S",
							"<cmd>lua require('diffview.actions').stage_all()<CR>",
							{ desc = "Stage all" },
						},
						{
							"n",
							"U",
							"<cmd>lua require('diffview.actions').unstage_all()<CR>",
							{ desc = "Unstage all" },
						},
						{
							"n",
							"X",
							"<cmd>lua require('diffview.actions').restore_entry()<CR>",
							{ desc = "Restore entry" },
						},
						{
							"n",
							"L",
							"<cmd>lua require('diffview.actions').open_commit_log()<CR>",
							{ desc = "Open commit log" },
						},
						{
							"n",
							"g<C-x>",
							"<cmd>lua require('diffview.actions').cycle_layout()<CR>",
							{ desc = "Cycle layout" },
						},
						{
							"n",
							"zo",
							"<cmd>lua require('diffview.actions').open_fold()<CR>",
							{ desc = "Open fold" },
						},
						{
							"n",
							"h",
							"<cmd>lua require('diffview.actions').close_fold()<CR>",
							{ desc = "Close fold" },
						},
						{
							"n",
							"zc",
							"<cmd>lua require('diffview.actions').close_fold()<CR>",
							{ desc = "Close fold" },
						},
						{
							"n",
							"za",
							"<cmd>lua require('diffview.actions').toggle_fold()<CR>",
							{ desc = "Toggle fold" },
						},
						{
							"n",
							"zR",
							"<cmd>lua require('diffview.actions').open_all_folds()<CR>",
							{ desc = "Open all folds" },
						},
						{
							"n",
							"zM",
							"<cmd>lua require('diffview.actions').close_all_folds()<CR>",
							{ desc = "Close all folds" },
						},
						{
							"n",
							"<c-b>",
							"<cmd>lua require('diffview.actions').scroll_view(-0.25)<CR>",
							{ desc = "Scroll up" },
						},
						{
							"n",
							"<c-f>",
							"<cmd>lua require('diffview.actions').scroll_view(0.25)<CR>",
							{ desc = "Scroll down" },
						},
						{
							"n",
							"<tab>",
							"<cmd>lua require('diffview.actions').select_next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"<s-tab>",
							"<cmd>lua require('diffview.actions').select_prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"gf",
							"<cmd>lua require('diffview.actions').goto_file_edit()<CR>",
							{ desc = "Open file in current window" },
						},
						{
							"n",
							"<C-w><C-f>",
							"<cmd>lua require('diffview.actions').goto_file_split()<CR>",
							{ desc = "Open file in split" },
						},
						{
							"n",
							"<C-w>gf",
							"<cmd>lua require('diffview.actions').goto_file_tab()<CR>",
							{ desc = "Open file in new tab" },
						},
						{
							"n",
							"i",
							"<cmd>lua require('diffview.actions').listing_style()<CR>",
							{ desc = "Toggle list style" },
						},
						{
							"n",
							"f",
							"<cmd>lua require('diffview.actions').toggle_flatten_dirs()<CR>",
							{ desc = "Toggle flatten" },
						},
						{
							"n",
							"R",
							"<cmd>lua require('diffview.actions').refresh_files()<CR>",
							{ desc = "Refresh files" },
						},
						{
							"n",
							"<leader>df",
							"<cmd>lua require('diffview.actions').focus_files()<CR>",
							{ desc = "Focus file panel" },
						},
						{
							"n",
							"<leader>b",
							"<cmd>lua require('diffview.actions').toggle_files()<CR>",
							{ desc = "Toggle file panel" },
						},
						{
							"n",
							"g<C-x>",
							"<cmd>lua require('diffview.actions').cycle_layout()<CR>",
							{ desc = "Cycle layout" },
						},
						{
							"n",
							"[x",
							"<cmd>lua require('diffview.actions').prev_conflict()<CR>",
							{ desc = "Previous conflict" },
						},
						{
							"n",
							"]x",
							"<cmd>lua require('diffview.actions').next_conflict()<CR>",
							{ desc = "Next conflict" },
						},
						{
							"n",
							"g?",
							"<cmd>lua require('diffview.actions').help('file_panel')<CR>",
							{ desc = "Show help" },
						},
						{
							"n",
							"<leader>cO",
							"<cmd>lua require('diffview.actions').conflict_choose_all('ours')<CR>",
							{ desc = "Choose all OURS" },
						},
						{
							"n",
							"<leader>cT",
							"<cmd>lua require('diffview.actions').conflict_choose_all('theirs')<CR>",
							{ desc = "Choose all THEIRS" },
						},
						{
							"n",
							"<leader>cB",
							"<cmd>lua require('diffview.actions').conflict_choose_all('base')<CR>",
							{ desc = "Choose all BASE" },
						},
						{
							"n",
							"<leader>cA",
							"<cmd>lua require('diffview.actions').conflict_choose_all('all')<CR>",
							{ desc = "Choose all ALL" },
						},
						{
							"n",
							"dX",
							"<cmd>lua require('diffview.actions').conflict_choose_all('none')<CR>",
							{ desc = "Delete all conflicts" },
						},
					},
					file_history_panel = {
						{
							"n",
							"g!",
							"<cmd>lua require('diffview.actions').options()<CR>",
							{ desc = "Options" },
						},
						{
							"n",
							"<C-A-d>",
							"<cmd>lua require('diffview.actions').open_in_diffview()<CR>",
							{ desc = "Open in diffview" },
						},
						{
							"n",
							"y",
							"<cmd>lua require('diffview.actions').copy_hash()<CR>",
							{ desc = "Copy commit hash" },
						},
						{
							"n",
							"L",
							"<cmd>lua require('diffview.actions').open_commit_log()<CR>",
							{ desc = "Open commit log" },
						},
						{
							"n",
							"X",
							"<cmd>lua require('diffview.actions').restore_entry()<CR>",
							{ desc = "Restore file" },
						},
						{
							"n",
							"zo",
							"<cmd>lua require('diffview.actions').open_fold()<CR>",
							{ desc = "Open fold" },
						},
						{
							"n",
							"zc",
							"<cmd>lua require('diffview.actions').close_fold()<CR>",
							{ desc = "Close fold" },
						},
						{
							"n",
							"h",
							"<cmd>lua require('diffview.actions').close_fold()<CR>",
							{ desc = "Close fold" },
						},
						{
							"n",
							"za",
							"<cmd>lua require('diffview.actions').toggle_fold()<CR>",
							{ desc = "Toggle fold" },
						},
						{
							"n",
							"zR",
							"<cmd>lua require('diffview.actions').open_all_folds()<CR>",
							{ desc = "Open all folds" },
						},
						{
							"n",
							"zM",
							"<cmd>lua require('diffview.actions').close_all_folds()<CR>",
							{ desc = "Close all folds" },
						},
						{
							"n",
							"j",
							"<cmd>lua require('diffview.actions').next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"<down>",
							"<cmd>lua require('diffview.actions').next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"k",
							"<cmd>lua require('diffview.actions').prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"<up>",
							"<cmd>lua require('diffview.actions').prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"<cr>",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"o",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"l",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"<2-LeftMouse>",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"<c-b>",
							"<cmd>lua require('diffview.actions').scroll_view(-0.25)<CR>",
							{ desc = "Scroll up" },
						},
						{
							"n",
							"<c-f>",
							"<cmd>lua require('diffview.actions').scroll_view(0.25)<CR>",
							{ desc = "Scroll down" },
						},
						{
							"n",
							"<tab>",
							"<cmd>lua require('diffview.actions').select_next_entry()<CR>",
							{ desc = "Next entry" },
						},
						{
							"n",
							"<s-tab>",
							"<cmd>lua require('diffview.actions').select_prev_entry()<CR>",
							{ desc = "Previous entry" },
						},
						{
							"n",
							"gf",
							"<cmd>lua require('diffview.actions').goto_file_edit()<CR>",
							{ desc = "Open file in current window" },
						},
						{
							"n",
							"<C-w><C-f>",
							"<cmd>lua require('diffview.actions').goto_file_split()<CR>",
							{ desc = "Open file in split" },
						},
						{
							"n",
							"<C-w>gf",
							"<cmd>lua require('diffview.actions').goto_file_tab()<CR>",
							{ desc = "Open file in new tab" },
						},
						{
							"n",
							"<leader>df",
							"<cmd>lua require('diffview.actions').focus_files()<CR>",
							{ desc = "Focus file panel" },
						},
						{
							"n",
							"<leader>b",
							"<cmd>lua require('diffview.actions').toggle_files()<CR>",
							{ desc = "Toggle file panel" },
						},
						{
							"n",
							"g<C-x>",
							"<cmd>lua require('diffview.actions').cycle_layout()<CR>",
							{ desc = "Cycle layout" },
						},
						{
							"n",
							"g?",
							"<cmd>lua require('diffview.actions').help('file_history_panel')<CR>",
							{ desc = "Show help" },
						},
					},
					option_panel = {
						{
							"n",
							"<tab>",
							"<cmd>lua require('diffview.actions').select_entry()<CR>",
							{ desc = "Select entry" },
						},
						{
							"n",
							"q",
							"<cmd>lua require('diffview.actions').close()<CR>",
							{ desc = "Close panel" },
						},
						{
							"n",
							"g?",
							"<cmd>lua require('diffview.actions').help('option_panel')<CR>",
							{ desc = "Show help" },
						},
					},
					help_panel = {
						{ "n", "q", "<cmd>lua require('diffview.actions').close()<CR>", { desc = "Close help" } },
					},
				},
			})
		end,
	},
}
