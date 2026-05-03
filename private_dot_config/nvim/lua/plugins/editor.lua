return {
	-- Treesitter
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		build = ":TSUpdate",
		lazy = false,
		opts = {
			install_dir = vim.fn.stdpath("data") .. "/site",
			languages = {
				"bash",
				"c",
				"diff",
				"html",
				"javascript",
				"jsdoc",
				"json",
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
				"kotlin",
				"go",
				"gomod",
				"gowork",
				"gosum",
				"rust",
			},
			filetypes = {
				"bash",
				"c",
				"cpp",
				"diff",
				"go",
				"gomod",
				"gosum",
				"gowork",
				"help",
				"html",
				"hcl",
				"javascript",
				"javascriptreact",
				"json",
				"jsonc",
				"kotlin",
				"lua",
				"markdown",
				"python",
				"query",
				"rust",
				"terraform",
				"terraform-vars",
				"toml",
				"tsx",
				"typescript",
				"typescriptreact",
				"vim",
				"yaml",
			},
			indent_filetypes = {
				"bash",
				"c",
				"cpp",
				"go",
				"gomod",
				"gosum",
				"gowork",
				"html",
				"hcl",
				"javascript",
				"javascriptreact",
				"json",
				"jsonc",
				"kotlin",
				"lua",
				"python",
				"terraform",
				"terraform-vars",
				"toml",
				"tsx",
				"typescript",
				"typescriptreact",
				"vim",
				"yaml",
			},
		},
		config = function(_, opts)
			local treesitter = require("nvim-treesitter")
			local treesitter_utils = require("utils.treesitter")
			local install_languages = treesitter_utils.resolve_languages(opts.languages)
			if type(treesitter.setup) == "function" then
				treesitter.setup({
					install_dir = opts.install_dir,
				})
			end

			local installed = {}
			if type(treesitter.get_installed) == "function" then
				installed = treesitter.get_installed()
			else
				local ok, info = pcall(require, "nvim-treesitter.info")
				if ok and type(info.installed_parsers) == "function" then
					installed = info.installed_parsers()
				end
			end
			local missing = vim.tbl_filter(function(language)
				return not vim.tbl_contains(installed, language)
			end, install_languages)
			if #missing > 0 and type(treesitter.install) == "function" then
				treesitter.install(missing)
			end

			vim.api.nvim_create_autocmd("FileType", {
				pattern = opts.filetypes,
				callback = function(args)
					treesitter_utils.start(args.buf, opts.indent_filetypes)
				end,
			})
		end,
	},

	-- Treesitter textobjects
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		enabled = false,
		event = "VeryLazy",
		dependencies = { "nvim-treesitter/nvim-treesitter" },
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
			-- Image floating preview felt awkward in WezTerm; browser preview (mkdp)
			-- is used for rich viewing instead. img-clip handles paste independently.
			image = { enabled = false },
		},
	},

	-- Paste images from clipboard into markdown as ![](path) links
	{
		"HakonHarnes/img-clip.nvim",
		ft = { "markdown" },
		opts = {
			default = {
				dir_path = "assets",
				relative_to_current_file = true,
				prompt_for_file_name = false,
				file_name = "%Y%m%d-%H%M%S",
			},
		},
		keys = {
			{ "<C-v>", "<cmd>PasteImage<cr>", mode = "n", ft = "markdown", desc = "Paste image from clipboard" },
		},
	},

}
