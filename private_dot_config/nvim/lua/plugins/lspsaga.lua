return {
	-- lspsaga for enhanced LSP UI
	{
		"nvimdev/lspsaga.nvim",
		enabled = true,
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
			"nvim-tree/nvim-web-devicons",
		},
		config = function()
			require("lspsaga").setup({
				ui = {
					border = "rounded",
					devicon = true,
					title = true,
					winblend = 10,
					expand = "",
					collapse = "",
					code_action = "💡",
					incoming = "📥 ",
					outgoing = "📤 ",
				},
				hover = {
					max_width = 0.6,
					max_height = 0.8,
					open_link = "gx",
					open_browser = "!open",
				},
				diagnostic = {
					show_code_action = true,
					show_source = true,
					jump_num_shortcut = true,
					max_width = 0.7,
					max_height = 0.6,
					text_hl_follow = true,
					border_follow = true,
					keys = {
						exec_action = "o",
						quit = { "q", "<ESC>" },
						toggle_or_jump = "<CR>",
						quit_in_show = { "q", "<ESC>" },
					},
				},
				code_action = {
					num_shortcut = true,
					show_server_name = false,
					extend_gitsigns = true,
					keys = {
						quit = { "q", "<ESC>" },
						exec = "<CR>",
					},
				},
				lightbulb = {
					enable = true,
					sign = true,
					virtual_text = false,
					debounce = 10,
					sign_priority = 40,
				},
				rename = {
					in_select = false,
					auto_save = false,
					project_max_width = 0.5,
					project_max_height = 0.5,
					keys = {
						quit = { "<C-c>", "<ESC>" },
						exec = "<CR>",
						select = "x",
					},
				},
				symbol_in_winbar = {
					enable = false, -- シンボル表示を無効化
				},
				outline = {
					enable = false, -- アウトライン機能を無効化
				},
				beacon = {
					enable = true,
					frequency = 7,
				},
			})

			-- キーマップの設定
			local opts = { noremap = true, silent = true }

			-- Definition Preview (条件付きで設定)
			local function setup_lsp_keymaps()
				local clients = vim.lsp.get_clients({ bufnr = 0 })
				if #clients > 0 then
					-- gd: 単一ヒットなら即ジャンプさせたいため、glance ではなく lspsaga を使用
					vim.keymap.set(
						"n",
						"gd",
						"<cmd>Lspsaga goto_definition<CR>",
						vim.tbl_extend("force", opts, { desc = "Go to Definition", buffer = true })
					)
					vim.keymap.set(
						"n",
						"gp",
						"<cmd>Glance definitions<CR>",
						vim.tbl_extend("force", opts, { desc = "Peek Definition", buffer = true })
					)
					vim.keymap.set(
						"n",
						"gt",
						"<cmd>Glance type_definitions<CR>",
						vim.tbl_extend("force", opts, { desc = "Peek Type Definition", buffer = true })
					)
					vim.keymap.set(
						"n",
						"gD",
						vim.lsp.buf.declaration,
						vim.tbl_extend("force", opts, { desc = "Go to Declaration", buffer = true })
					)
					vim.keymap.set(
						"n",
						"gi",
						"<cmd>Glance implementations<CR>",
						vim.tbl_extend("force", opts, { desc = "Go to Implementation", buffer = true })
					)
					vim.keymap.set(
						"n",
						"gr",
						"<cmd>Glance references<CR>",
						vim.tbl_extend("force", opts, { desc = "Find References", buffer = true })
					)

					-- Additional LSP keymaps
					vim.keymap.set(
						"n",
						"<C-k>",
						vim.lsp.buf.signature_help,
						vim.tbl_extend("force", opts, { desc = "Signature Help", buffer = true })
					)
					vim.keymap.set(
						"n",
						"<space>ca",
						"<cmd>Lspsaga code_action<CR>",
						vim.tbl_extend("force", opts, { desc = "Code Action", buffer = true })
					)
					vim.keymap.set("n", "<space>f", function()
						require("utils.format").format(nil, { save = false })
					end, vim.tbl_extend("force", opts, { desc = "Format", buffer = true }))
				end
			end

			-- LSPアタッチ時にキーマップを設定
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function()
					setup_lsp_keymaps()
				end,
			})

			-- Enhanced Hover
			vim.keymap.set(
				"n",
				"K",
				"<cmd>Lspsaga hover_doc<CR>",
				vim.tbl_extend("force", opts, { desc = "Hover Documentation" })
			)

			-- Enhanced Diagnostics Navigation
			vim.keymap.set(
				"n",
				"[d",
				"<cmd>Lspsaga diagnostic_jump_prev<CR>",
				vim.tbl_extend("force", opts, { desc = "Previous Diagnostic" })
			)
			vim.keymap.set(
				"n",
				"]d",
				"<cmd>Lspsaga diagnostic_jump_next<CR>",
				vim.tbl_extend("force", opts, { desc = "Next Diagnostic" })
			)
			vim.keymap.set(
				"n",
				"<leader>d",
				"<cmd>Lspsaga show_line_diagnostics<CR>",
				vim.tbl_extend("force", opts, { desc = "Show Line Diagnostics" })
			)
			vim.keymap.set(
				"n",
				"<leader>D",
				"<cmd>Lspsaga show_cursor_diagnostics<CR>",
				vim.tbl_extend("force", opts, { desc = "Show Cursor Diagnostics" })
			)

			-- Call Hierarchy
			vim.keymap.set(
				"n",
				"<leader>ci",
				"<cmd>Lspsaga incoming_calls<CR>",
				vim.tbl_extend("force", opts, { desc = "Incoming Calls" })
			)
			vim.keymap.set(
				"n",
				"<leader>co",
				"<cmd>Lspsaga outgoing_calls<CR>",
				vim.tbl_extend("force", opts, { desc = "Outgoing Calls" })
			)

			-- Enhanced Rename
			vim.keymap.set(
				"n",
				"<leader>rn",
				"<cmd>Lspsaga rename<CR>",
				vim.tbl_extend("force", opts, { desc = "LSP Saga Rename" })
			)

			-- LSP Restart (full restart of all clients attached to current buffer)
			vim.keymap.set("n", "<leader>lr", function()
				local bufnr = vim.api.nvim_get_current_buf()
				local clients = vim.lsp.get_clients({ bufnr = bufnr })
				if #clients == 0 then
					vim.notify("No LSP clients attached", vim.log.levels.WARN)
					return
				end

				local client_names = {}
				for _, client in ipairs(clients) do
					table.insert(client_names, client.name)
					client.stop()
				end

				vim.defer_fn(function()
					vim.cmd("edit")
					vim.notify("LSP restarted: " .. table.concat(client_names, ", "), vim.log.levels.INFO)
				end, 500)
			end, vim.tbl_extend("force", opts, { desc = "LSP Restart" }))
		end,
		event = { "BufReadPre", "BufNewFile" }, -- LSP より前に必ずロード
	},
}
