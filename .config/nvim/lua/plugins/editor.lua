return {
	-- Treesitter
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "master",
		build = ":TSUpdate",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			sync_install = false,
			ensure_installed = {
				"bash",
				"c",
				"diff",
				"html",
				"javascript",
				"jsdoc",
				"json",
				"jsonc",
				"lua",
				"luadoc",
				"luap",
				"markdown",
				"markdown_inline",
				"python",
				"query",
				"regex",
				"toml",
				"tsx",
				"typescript",
				"vim",
				"vimdoc",
				"yaml",
				"go",
				"gomod",
				"gowork",
				"gosum",
				"rust",
			},
			highlight = { enable = true },
			indent = {
				enable = true,
				disable = { "rust" }, -- cannot correctly handle Rust macro calls
			},
		},
		config = function(_, opts)
			require("nvim-treesitter.configs").setup(opts)
		end,
	},

	-- Treesitter textobjects
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		event = "VeryLazy",
		enabled = true,
		config = function()
			if vim.g.lazy_load_treesitter then
				local plugin = require("lazy.core.config").spec.plugins["nvim-treesitter"]
				require("lazy.core.loader").load(plugin, { event = "VeryLazy" })
			end
		end,
	},

	-- Auto pairs
	{
		"windwp/nvim-autopairs",
		event = "InsertEnter",
		config = function()
			require("nvim-autopairs").setup({
				check_ts = true,
				ts_config = {
					lua = { "string", "source" },
					javascript = { "string", "template_string" },
					java = false,
				},
				disable_filetype = { "TelescopePrompt", "spectre_panel" },
				fast_wrap = {
					map = "<M-e>",
					chars = { "{", "[", "(", '"', "'" },
					pattern = string.gsub([[ [%'%"%)%>%]%)%}%,] ]], "%s+", ""),
					offset = 0,
					end_key = "$",
					keys = "qwertyuiopzxcvbnmasdfghjkl",
					check_comma = true,
					highlight = "PmenuSel",
					highlight_grey = "LineNr",
				},
			})

			local npairs = require("nvim-autopairs")
			local Rule = require("nvim-autopairs.rule")
			local cond = require("nvim-autopairs.conds")

			npairs.add_rules({
				Rule("$", "$", { "tex", "latex" })
					:with_pair(cond.not_after_regex("%%"))
					:with_pair(cond.not_before_regex("xxx", 3))
					:with_move(cond.none())
					:with_del(cond.not_after_regex("xx"))
					:with_cr(cond.none()),
			})
		end,
	},

	-- Comment
	{
		"numToStr/Comment.nvim",
		dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
		opts = function()
			local ok, ts_integ = pcall(require, "ts_context_commentstring.integrations.comment_nvim")
			return {
				pre_hook = ok and ts_integ.create_pre_hook() or nil,
			}
		end,
		lazy = false,
	},

	-- Context-aware commentstring (JSX/TSX 等)
	{
		"JoosepAlviste/nvim-ts-context-commentstring",
		opts = { enable_autocmd = false },
	},

	-- Todo comments
	{
		"folke/todo-comments.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		opts = {},
	},

	-- Smart splits for window navigation
	{
		"mrjones2014/smart-splits.nvim",
		opts = {
			default_amount = 3,
		},
		keys = {
			{ "<A-h>", function() require("smart-splits").resize_left() end, desc = "Resize left" },
			{ "<A-j>", function() require("smart-splits").resize_down() end, desc = "Resize down" },
			{ "<A-k>", function() require("smart-splits").resize_up() end, desc = "Resize up" },
			{ "<A-l>", function() require("smart-splits").resize_right() end, desc = "Resize right" },
		},
	},

	-- Better escape
	{
		"max397574/better-escape.nvim",
		enabled = false,
	},

	-- Guess indent
	{
		"NMAC427/guess-indent.nvim",
		opts = {},
	},

	-- Snacks (modern UI components)
	{
		"folke/snacks.nvim",
		priority = 1000,
		lazy = false,
		opts = {
			modules = { "scratch", "picker" },
			picker = {
				ui_select = true,
				layouts = {
					cursor = {
						preview = false,
						layout = {
							backdrop = false,
							row = 1,
							col = 0.3,
							width = 60,
							height = 15,
							min_height = 3,
							border = "rounded",
							title = "{title}",
							title_pos = "center",
							box = "vertical",
							{ win = "input", height = 1, border = "bottom" },
							{ win = "list", border = "none" },
						},
					},
				},
			},
		},
	},

	-- Markdown rendering for Octo buffers (markview handles regular markdown)
	{
		"MeanderingProgrammer/render-markdown.nvim",
		dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
		ft = { "octo" },
		config = function(_, opts)
			vim.treesitter.language.register("markdown", "octo")
			require("render-markdown").setup(opts)
		end,
		opts = {
			file_types = { "octo" },
			render_modes = { "n", "c" },
			heading = {
				icons = { "󰎤 ", "󰎧 ", "󰎪 ", "󰎭 ", "󰎱 ", "󰎳 " },
				backgrounds = {
					"RenderMarkdownH1Bg",
					"RenderMarkdownH2Bg",
					"RenderMarkdownH3Bg",
					"RenderMarkdownH4Bg",
					"RenderMarkdownH5Bg",
					"RenderMarkdownH6Bg",
				},
			},
			code = {
				sign = false,
				width = "block",
				right_pad = 1,
			},
			pipe_table = {
				style = "full",
				cell = "padded",
			},
		},
	},
}
