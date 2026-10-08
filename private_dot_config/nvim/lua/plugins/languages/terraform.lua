return {
	{
		"nvim-treesitter/nvim-treesitter",
		opts = function(_, opts)
			return require("utils.treesitter").extend(opts, {
				languages = { "terraform", "hcl" },
				filetypes = { "terraform", "hcl", "terraform-vars" },
				indent_filetypes = { "terraform", "hcl", "terraform-vars" },
			})
		end,
	},

	{
		"terraform-lsp-setup",
		virtual = true,
		ft = { "terraform", "hcl", "terraform-vars" },
		cond = not vim.g.vscode,
		dependencies = { "neovim/nvim-lspconfig", "nvimtools/none-ls.nvim" },
		config = function()
			-- Configure terraform-ls
			vim.lsp.config("terraform_ls", {
				cmd = { "terraform-ls", "serve" },
				root_markers = { ".terraform", ".git" },
				filetypes = { "terraform", "hcl", "terraform-vars" },
			})

			vim.lsp.enable("terraform_ls")

			-- Setup null-ls for formatting and linting
			local ok_null, null_ls = pcall(require, "null-ls")
			if not ok_null then
				return
			end

			-- Terraform fmt formatter
			local terraform_fmt = {
				method = null_ls.methods.FORMATTING,
				filetypes = { "terraform", "hcl", "terraform-vars" },
				generator = null_ls.formatter({
					command = "terraform",
					args = { "fmt", "-" },
					to_stdin = true,
				}),
			}

			-- tflint diagnostics
			local tflint_diagnostics = {
				method = null_ls.methods.DIAGNOSTICS,
				filetypes = { "terraform", "hcl" },
				generator = null_ls.generator({
					command = "tflint",
					args = { "--format", "json" },
					-- tflint lints the directory it runs in; null-ls would run it in the root of its project
					cwd = function(params)
						return vim.fs.dirname(params.bufname)
					end,
					-- `nvim new/main.tf`: null-ls fails to spawn in a directory that does not exist and stops
					-- using the source, and tflint in the project root would report the files found there
					runtime_condition = function(params)
						return vim.uv.fs_stat(vim.fs.dirname(params.bufname)) ~= nil
					end,
					to_stdin = false,
					from_stderr = false,
					-- tflint exits with 1 for a file with a syntax error; null-ls takes that for an error of
					-- the generator and stops using the source
					ignore_stderr = true,
					format = "json",
					check_exit_code = { 0, 2 },
					on_output = function(params)
						local diagnostics = {}
						-- tflint reports the issues of every file in the directory
						local filename = vim.fs.basename(params.bufname)
						if params.output and params.output.issues then
							for _, issue in ipairs(params.output.issues) do
								if issue.range and issue.range.filename == filename then
									table.insert(diagnostics, {
										row = issue.range.start.line,
										col = issue.range.start.column,
										end_row = issue.range["end"].line,
										end_col = issue.range["end"].column,
										source = "tflint",
										message = issue.message,
										code = issue.rule.name,
										severity = issue.rule.severity == "error" and 1 or 2,
									})
								end
							end
						end
						return diagnostics
					end,
				}),
			}

			null_ls.register(terraform_fmt)
			null_ls.register(tflint_diagnostics)

			-- Keymaps: integrate lsp-actions for Terraform
			local lsp_actions = require("utils.lsp-actions")

			vim.api.nvim_create_autocmd("FileType", {
				pattern = { "terraform", "hcl", "terraform-vars" },
				callback = function()
					local opts = { buffer = true, silent = true }

					vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
					vim.keymap.set("n", "<D-S-r>", lsp_actions.terraform_refactor_menu, opts)
					vim.keymap.set("n", "<M-S-r>", lsp_actions.terraform_refactor_menu, opts)
				end,
			})
		end,
	},
}
