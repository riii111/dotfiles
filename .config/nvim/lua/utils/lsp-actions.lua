local M = {}

local function get_current_line_diagnostics()
	return vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
end

local function create_code_action_context(only_types)
	return {
		only = only_types or { "quickfix", "refactor" },
		diagnostics = get_current_line_diagnostics(),
	}
end

local function execute_menu_choice(choice, cmd_patterns)
	if not choice then
		return
	end

	if #cmd_patterns > 0 then
		for _, pattern_handler in ipairs(cmd_patterns) do
			local pattern = pattern_handler[1]
			local handler = pattern_handler[2]
			if choice:match(pattern) then
				handler(choice)
				return
			end
		end
	else
		-- Fallback to pairs for backward compatibility
		for pattern, handler in pairs(cmd_patterns) do
			if choice:match(pattern) then
				handler(choice)
				return
			end
		end
	end
end

function M.smart_code_action()
	vim.lsp.buf.code_action({
		context = create_code_action_context(),
		apply = true,
	})
end

function M.rust_quick_actions()
	local options = {
		"Code Action - Show available actions",
		"RustLsp explainError - Explain error",
		"RustLsp renderDiagnostic - Show diagnostic",
		"RustLsp relatedDiagnostics - Related diagnostics",
		"RustLsp hover actions - Hover actions",
	}

	vim.ui.select(options, {
		prompt = "Rust Quick Fix:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^(RustLsp [^-]+)",
				function(c)
					vim.cmd(c:match("^(RustLsp [^-]+)"))
				end,
			},
		})
	end)
end

function M.go_quick_actions()
	local go_actions = {
		"Code Action - Show available actions",
		"GoIfErr - Add error handling",
		"GoFillStruct - Fill struct",
		"GoImpl - Implement interface",
	}

	vim.ui.select(go_actions, {
		prompt = "Go Quick Fix:",
		layout = "cursor",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^(%S+)",
				function(c)
					vim.cmd(c:match("^(%S+)"))
				end,
			},
		})
	end)
end

function M.language_specific_code_action()
	local filetype = vim.bo.filetype

	local params = vim.lsp.util.make_position_params(0, "utf-16")
	local actions = vim.lsp.buf_request_sync(0, "textDocument/codeAction", {
		textDocument = vim.lsp.util.make_text_document_params(0),
		range = { start = params.position, ["end"] = params.position },
		context = create_code_action_context(),
	}, 1000)

	local valid_actions = {}
	if actions then
		for _, client_actions in pairs(actions) do
			if client_actions.result then
				for _, action in ipairs(client_actions.result) do
					table.insert(valid_actions, action)
				end
			end
		end
	end

	if valid_actions and #valid_actions > 0 then
		if #valid_actions == 1 and filetype ~= "python" then
			vim.lsp.buf.code_action({ apply = true })
		else
			vim.lsp.buf.code_action()
		end
	else
		if filetype == "rust" then
			M.rust_quick_actions()
		elseif filetype == "go" then
			M.go_quick_actions()
		elseif filetype == "c" or filetype == "cpp" or filetype == "objc" or filetype == "objcpp" then
			if M.cpp_quick_actions then
				M.cpp_quick_actions()
			else
				vim.lsp.buf.code_action()
			end
		elseif filetype == "python" then
			M.python_quick_actions()
		elseif
			filetype == "typescript"
			or filetype == "typescriptreact"
			or filetype == "javascript"
			or filetype == "javascriptreact"
		then
			M.typescript_quick_actions()
		elseif filetype == "terraform" or filetype == "hcl" or filetype == "terraform-vars" then
			M.terraform_quick_actions()
		elseif filetype == "kotlin" then
			M.kotlin_quick_actions()
		elseif filetype == "lua" then
			M.lua_quick_actions()
		else
			local generic_options = {
				"Rename - Rename symbol",
				"Code Action - Show available actions",
			}

			vim.ui.select(generic_options, {
				prompt = "Select Action:",
			}, function(choice)
				execute_menu_choice(choice, {
					{
						"^Rename",
						function()
							vim.lsp.buf.rename()
						end,
					},
					{
						".",
						function()
							local has_lspsaga = pcall(require, "lspsaga")
							if has_lspsaga then
								vim.cmd("Lspsaga code_action")
							else
								vim.lsp.buf.code_action()
							end
						end,
					},
				})
			end)
		end
	end
end

function M.rust_refactor_menu()
	local options = {
		"RustLsp expandMacro - Expand macro",
		"RustLsp moveItem up - Move item up",
		"RustLsp moveItem down - Move item down",
		"RustLsp ssr - Structural search replace",
		"RustLsp joinLines - Join lines",
		"RustLsp hover actions - Hover actions",
		"RustLsp openCargo - Open Cargo.toml",
		"RustLsp parentModule - Go to parent module",
		"Rename - Rename symbol",
	}

	vim.ui.select(options, {
		prompt = "Select Refactoring:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^(RustLsp [^-]+)",
				function(c)
					vim.cmd(c:match("^(RustLsp [^-]+)"))
				end,
			},
		})
	end)
end

function M.go_refactor_menu()
	local options = {
		"GoIfErr - Add if err != nil",
		"GoFillStruct - Fill struct fields",
		"GoFixPlurals - Fix plural parameters",
		"GoAddTag json - Add JSON tags",
		"GoAddTag yaml - Add YAML tags",
		"GoRmTag - Remove tags",
		"GoImpl - Implement interface",
		"GoGenReturn - Generate return statement",
		"GoCmt - Add comments",
		"Rename - Rename symbol",
	}

	vim.ui.select(options, {
		prompt = "Select Refactoring:",
		layout = "cursor",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^GoAddTag",
				function(c)
					local tag = c:match("(%w+)$")
					vim.cmd("GoAddTag " .. tag)
				end,
			},
			{
				"^(%S+)",
				function(c)
					vim.cmd(c:match("^(%S+)"))
				end,
			},
		})
	end)
end

function M.python_quick_actions()
	local options = {
		"Code Action - Show available actions",
		"Organize Imports - Sort and clean imports",
		"Add Type Annotation - Add type hints",
		"Run File - Execute current Python file",
		"Run Tests - Execute pytest",
		"Toggle Docstring - Add/update docstring",
		"Black Format - Format with Black",
	}

	vim.ui.select(options, {
		prompt = "Python Quick Fix:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^Organize Imports",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.organizeImports" } },
						apply = true,
					})
				end,
			},
			{
				"^Add Type",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "quickfix", "refactor.rewrite" } },
						apply = false,
					})
				end,
			},
			{
				"^Run File",
				function()
					local file = vim.fn.expand("%:p")
					vim.cmd("split | terminal python " .. file)
				end,
			},
			{
				"^Run Tests",
				function()
					vim.cmd("split | terminal python -m pytest")
				end,
			},
			{
				"^Toggle Docstring",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.rewrite" } },
						apply = false,
					})
				end,
			},
			{
				"^Black Format",
				function()
					require("utils.format").format(nil, { save = false })
				end,
			},
		})
	end)
end

function M.python_refactor_menu()
	local options = {
		"Organize Imports - Sort and optimize imports",
		"Extract Method - Extract selected code to method",
		"Extract Variable - Extract expression to variable",
		"Inline Variable - Inline variable usage",
		"Add Type Annotations - Add type hints to function",
		"Generate Docstring - Add documentation",
		"Convert to f-string - Modernize string formatting",
		"Rename - Rename symbol",
	}

	vim.ui.select(options, {
		prompt = "Select Refactoring:",
		layout = "cursor",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^Organize Imports",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.organizeImports" } },
						apply = true,
					})
				end,
			},
			{
				"^Extract",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.extract" } },
						apply = false,
					})
				end,
			},
			{
				"^Inline",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.inline" } },
						apply = false,
					})
				end,
			},
			{
				"^Add Type",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "quickfix", "refactor.rewrite" } },
						apply = false,
					})
				end,
			},
			{
				"^Generate",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.rewrite" } },
						apply = false,
					})
				end,
			},
			{
				"^Convert",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "quickfix", "refactor.rewrite" } },
						apply = false,
					})
				end,
			},
		})
	end)
end

function M.cpp_quick_actions()
	local options = {
		"Code Action - Show available actions",
		"Rename - Symbol rename",
		"Extract Function - Refactor extract",
		"Extract Variable - Refactor extract",
		"Inline - Refactor inline",
	}
	vim.ui.select(options, { prompt = "C/C++ Quick Fix:" }, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^Extract Function",
				function()
					vim.lsp.buf.code_action({ context = { only = { "refactor.extract" } } })
				end,
			},
			{
				"^Extract Variable",
				function()
					vim.lsp.buf.code_action({ context = { only = { "refactor.extract" } } })
				end,
			},
			{
				"^Inline",
				function()
					vim.lsp.buf.code_action({ context = { only = { "refactor.inline" } } })
				end,
			},
		})
	end)
end

function M.cpp_refactor_menu()
	local options = {
		"Rename",
		"Extract Function",
		"Extract Variable",
		"Inline",
	}
	vim.ui.select(options, { prompt = "Select Refactoring:" }, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^Extract",
				function()
					vim.lsp.buf.code_action({ context = { only = { "refactor.extract" } } })
				end,
			},
			{
				"^Inline",
				function()
					vim.lsp.buf.code_action({ context = { only = { "refactor.inline" } } })
				end,
			},
		})
	end)
end

function M.typescript_quick_actions()
	local options = {
		"Code Action - Show available actions",
		"Organize Imports - Sort and clean imports",
		"Add Missing Imports - Auto-import missing symbols",
		"Remove Unused Imports - Clean up imports",
	}

	vim.ui.select(options, {
		prompt = "TypeScript/JavaScript Quick Fix:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^Organize Imports",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.organizeImports" } },
						apply = true,
					})
				end,
			},
			{
				"^Add Missing",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.addMissingImports" } },
						apply = true,
					})
				end,
			},
			{
				"^Remove Unused",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.removeUnused" } },
						apply = true,
					})
				end,
			},
		})
	end)
end

function M.typescript_refactor_menu()
	local options = {
		"Rename - Rename symbol",
		"Extract Function - Extract to function",
		"Extract Variable - Extract to variable",
		"Organize Imports - Sort imports",
	}

	vim.ui.select(options, {
		prompt = "Select Refactoring:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^Extract Function",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.extract.function" } },
						apply = false,
					})
				end,
			},
			{
				"^Extract Variable",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.extract.constant" } },
						apply = false,
					})
				end,
			},
			{
				"^Organize",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.organizeImports" } },
						apply = true,
					})
				end,
			},
		})
	end)
end

function M.terraform_quick_actions()
	local options = {
		"Code Action - Show available actions",
		"Format Document - Run terraform fmt",
		"Validate - Validate Terraform configuration",
		"Rename - Rename resource/variable",
	}

	vim.ui.select(options, {
		prompt = "Terraform Quick Fix:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^Format Document",
				function()
					require("utils.format").format(nil, { save = false })
				end,
			},
			{
				"^Validate",
				function()
					vim.cmd("split | terminal terraform validate")
				end,
			},
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
		})
	end)
end

function M.terraform_refactor_menu()
	local options = {
		"Rename - Rename resource/variable/module",
		"Format Document - Run terraform fmt",
		"Code Action - Show available refactorings",
	}

	vim.ui.select(options, {
		prompt = "Select Refactoring:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^Format Document",
				function()
					require("utils.format").format(nil, { save = false })
				end,
			},
			{
				"^Code Action",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor" } },
						apply = false,
					})
				end,
			},
		})
	end)
end

function M.kotlin_quick_actions()
	local options = {
		"Code Action - Show available actions",
		"Organize Imports - Sort and clean imports",
		"Format with ktlint - Format current file",
		"Rename - Rename symbol",
	}

	vim.ui.select(options, {
		prompt = "Kotlin Quick Fix:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^Organize Imports",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.organizeImports" } },
						apply = true,
					})
				end,
			},
			{
				"^Format with ktlint",
				function()
					require("utils.format").format(nil, { save = false })
				end,
			},
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
		})
	end)
end

function M.kotlin_refactor_menu()
	local options = {
		"Rename - Rename symbol",
		"Extract Function - Extract to function",
		"Extract Variable - Extract to variable",
		"Organize Imports - Sort imports",
		"Format Document - Run ktlint format",
	}

	vim.ui.select(options, {
		prompt = "Select Refactoring:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^Extract Function",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.extract.function" } },
						apply = false,
					})
				end,
			},
			{
				"^Extract Variable",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor.extract.constant" } },
						apply = false,
					})
				end,
			},
			{
				"^Organize",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "source.organizeImports" } },
						apply = true,
					})
				end,
			},
			{
				"^Format Document",
				function()
					require("utils.format").format(nil, { save = false })
				end,
			},
		})
	end)
end

function M.lua_quick_actions()
	local options = {
		"Code Action - Show available actions",
		"Format with StyLua - Format current file",
		"Rename - Rename symbol",
	}

	vim.ui.select(options, {
		prompt = "Lua Quick Fix:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Code Action",
				function()
					local has_lspsaga = pcall(require, "lspsaga")
					if has_lspsaga then
						vim.cmd("Lspsaga code_action")
					else
						vim.lsp.buf.code_action()
					end
				end,
			},
			{
				"^Format with StyLua",
				function()
					require("utils.format").format(nil, { save = false })
				end,
			},
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
		})
	end)
end

function M.lua_refactor_menu()
	local options = {
		"Rename - Rename symbol",
		"Format Document - Run StyLua format",
		"Code Action - Show available refactorings",
	}

	vim.ui.select(options, {
		prompt = "Select Refactoring:",
	}, function(choice)
		execute_menu_choice(choice, {
			{
				"^Rename",
				function()
					vim.lsp.buf.rename()
				end,
			},
			{
				"^Format Document",
				function()
					require("utils.format").format(nil, { save = false })
				end,
			},
			{
				"^Code Action",
				function()
					vim.lsp.buf.code_action({
						context = { only = { "refactor" } },
						apply = false,
					})
				end,
			},
		})
	end)
end

return M
