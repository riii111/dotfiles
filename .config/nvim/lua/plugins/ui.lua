local function is_custom_theme()
	return vim.g.colors_name == "custom-theme-riii111"
end

local function get_colors()
	if is_custom_theme() then
		return require("custom-theme-riii111").palette()
	end
	return nil
end

return {

	-- Bufferline (crisidev style)
	{
		"akinsho/bufferline.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		version = "*",
		config = function()
			local colors = get_colors()

			local groups_items = {}
			local highlights = {
				fill = { bg = "NONE" },
				group_separator = { fg = "NONE", bg = "NONE" },
			}

			if colors then
				groups_items = {
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
						name = "kotlin",
						highlight = { fg = colors.languages.kotlin },
						priority = 5,
						auto_close = true,
						matcher = function(buf)
							return buf.name:match("%.kt$") or buf.name:match("%.kts$")
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
						highlight = { fg = colors.languages.jsx },
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
				}

				highlights = {
					fill = { bg = "NONE" },
					background = { fg = colors.base.fg_alt, bg = "NONE" },
					buffer = { fg = colors.base.fg_alt, bg = "NONE" },
					buffer_selected = { fg = colors.base.fg, bg = "NONE", bold = true },
					buffer_visible = { fg = colors.base.fg_alt, bg = "NONE" },
					tab = { fg = colors.base.fg_alt, bg = "NONE" },
					tab_selected = { fg = colors.base.fg, bg = "NONE", bold = true },
					tab_close = { fg = colors.base.fg_alt, bg = "NONE" },
					indicator_selected = { fg = "NONE", bg = "NONE" },
					indicator_visible = { fg = "NONE", bg = "NONE" },
					modified = { fg = colors.semantic.warning, bg = "NONE" },
					modified_selected = { fg = colors.semantic.warning, bg = "NONE" },
					modified_visible = { fg = colors.semantic.warning, bg = "NONE" },
					group_label = { fg = colors.base.fg_dark, bg = "NONE", bold = true },
					group_separator = { fg = "NONE", bg = "NONE" },
				}
			end

			require("bufferline").setup({
				options = {
					mode = "buffers",
					separator_style = { "", "" },
					indicator = { style = "none" },
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
						items = groups_items,
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
				highlights = highlights,
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
			local colors = get_colors()

			local incline_opts = {
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

					local path = vim.api.nvim_buf_get_name(props.buf)
					local segments = {}

					if path ~= "" then
						local parts = vim.split(path, "/")
						if #parts > 1 then
							local parent = parts[#parts - 1]
							local muted_color = colors and colors.base.fg_muted or nil
							table.insert(segments, { parent, guifg = muted_color })
							table.insert(segments, { " > ", guifg = muted_color })
						end
					end

					local fallback_color = colors and colors.base.white or nil
					table.insert(segments, { (icon and icon .. " " or ""), guifg = color or fallback_color })
					table.insert(segments, { filename, gui = "bold" })

					return segments
				end,
			}

			if colors then
				incline_opts.highlight = {
					groups = {
						InclineNormal = { guibg = colors.base.bg_medium, guifg = colors.base.fg_alt },
						InclineNormalNC = { guifg = colors.base.fg_muted, guibg = colors.base.bg_dark },
					},
				}
			end

			require("incline").setup(incline_opts)
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
					char = "│",
				},
				scope = {
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
			local colors = get_colors()

			local term_highlights = {
				Normal = { guibg = "NONE" },
				NormalFloat = { guibg = "NONE" },
			}

			if colors then
				term_highlights.FloatBorder = { guifg = colors.base.accent, guibg = colors.base.bg }
			end

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
				direction = "float",
				close_on_exit = true,
				shell = vim.o.shell,
				auto_scroll = true,
				float_opts = {
					border = "rounded",
					width = function()
						return math.floor(vim.o.columns * 0.9)
					end,
					height = function()
						return math.floor(vim.o.lines * 0.6)
					end,
					winblend = 0,
				},
				highlights = term_highlights,
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
				local kopts = { buffer = 0 }
				vim.keymap.set("t", "<esc>", [[<Cmd>ToggleTerm<CR>]], kopts)
				vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], kopts)
				vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], kopts)
				vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], kopts)
				vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], kopts)
				vim.keymap.set("t", "<C-w>", [[<C-\><C-n><C-w>]], kopts)
			end

			vim.cmd("autocmd! TermOpen term://* lua set_terminal_keymaps()")
		end,
	},

	-- Markdown rendering
	{
		"MeanderingProgrammer/render-markdown.nvim",
		ft = { "markdown" },
		dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
		opts = {
			file_types = { "markdown" },
			ignore = function(bufnr)
				return vim.bo[bufnr].filetype == "oil"
			end,
		},
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
}
