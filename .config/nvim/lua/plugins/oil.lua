return {
	"stevearc/oil.nvim",
	lazy = false,
	dependencies = { "echasnovski/mini.icons" },
	opts = {
		-- Take over directory buffers (e.g. `vim .` or `:e src/`)
		default_file_explorer = true,

		columns = {
			"icon",
			-- "permissions",
			-- "size",
			-- "mtime",
		},

		buf_options = {
			buflisted = false,
			bufhidden = "hide",
		},

		win_options = {
			wrap = false,
			signcolumn = "no",
			cursorcolumn = false,
			foldcolumn = "0",
			spell = false,
			list = false,
			conceallevel = 3,
			concealcursor = "nvic",
		},

		delete_to_trash = true,
		skip_confirm_for_simple_edits = false,
		prompt_save_on_select_new_entry = true,
		cleanup_delay_ms = 2000,

		lsp_file_methods = {
			enabled = true,
			timeout_ms = 1000,
			-- Autosave buffers that are updated with LSP willRenameFiles
			autosave_changes = true,
		},

		use_default_keymaps = true,

		view_options = {
			show_hidden = true,
			is_hidden_file = function(name)
				return vim.startswith(name, ".")
			end,
			is_always_hidden = function()
				return false
			end,
			natural_order = true,
			case_insensitive = false,
			sort = {
				{ "type", "asc" },
				{ "name", "asc" },
			},
		},

		float = {
			padding = 2,
			max_width = 0.9,
			max_height = 0.9,
			border = "rounded",
			win_options = {
				winblend = 0,
			},
		},

		preview = {
			max_width = 0.9,
			min_width = { 40, 0.4 },
			width = nil,
			max_height = 0.9,
			min_height = { 5, 0.1 },
			height = nil,
			border = "rounded",
			win_options = {
				winblend = 0,
			},
			update_on_cursor_moved = true,
		},

		keymaps = {
			["g?"] = "actions.show_help",
			["<CR>"] = "actions.select",
			["<C-s>"] = { "actions.select", opts = { vertical = true }, desc = "Open in vertical split" },
			["<C-h>"] = { "actions.select", opts = { horizontal = true }, desc = "Open in horizontal split" },
			["<C-t>"] = { "actions.select", opts = { tab = true }, desc = "Open in new tab" },
			["<C-p>"] = "actions.preview",
			["<C-c>"] = { "actions.close", mode = "n" },
			["<C-l>"] = "actions.refresh",
			["-"] = { "actions.parent", mode = "n" },
			["_"] = { "actions.open_cwd", mode = "n" },
			["`"] = { "actions.cd", mode = "n" },
			["~"] = { "actions.cd", opts = { scope = "tab" }, mode = "n" },
			["gs"] = { "actions.change_sort", mode = "n" },
			["gx"] = "actions.open_external",
			["g."] = { "actions.toggle_hidden", mode = "n" },
			["g\\"] = { "actions.toggle_trash", mode = "n" },

			-- Custom keymaps
			["<Esc>"] = { "actions.close", mode = "n" },
			["q"] = { "actions.close", mode = "n" },
			["<C-v>"] = { "actions.select", opts = { vertical = true }, desc = "Open in vertical split" },
		},
	},
	config = function(_, opts)
		require("oil").setup(opts)
		-- Restore default yank-on-delete in oil buffers so dd/p can move files
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "oil",
			callback = function()
				local bopts = { buffer = true }
				vim.keymap.set("n", "dd", "dd", bopts)
				vim.keymap.set("n", "d", "d", bopts)
				vim.keymap.set("v", "d", "d", bopts)
			end,
		})
	end,
}
