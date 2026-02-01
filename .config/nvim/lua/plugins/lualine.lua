-- Lazy-loaded module cache (populated on first use)
local _cache = {}
local _file_icon_color_cache = nil

local function get_devicons()
	if _cache.devicons == nil then
		local ok, mod = pcall(require, "nvim-web-devicons")
		if ok then
			_cache.devicons = mod
		end
	end
	return _cache.devicons
end

local function get_lazy_status()
	if _cache.lazy_status == nil then
		local ok, mod = pcall(require, "lazy.status")
		if ok then
			_cache.lazy_status = mod
		end
	end
	return _cache.lazy_status
end

local function get_treesitter_parsers()
	if _cache.ts_parsers == nil then
		local ok, mod = pcall(require, "nvim-treesitter.parsers")
		if ok then
			_cache.ts_parsers = mod
		end
	end
	return _cache.ts_parsers
end

local function get_dap()
	if _cache.dap == nil then
		local ok, mod = pcall(require, "dap")
		if ok then
			_cache.dap = mod
		end
	end
	return _cache.dap
end

local function is_custom_theme_active()
	return vim.g.colors_name == "custom-theme-riii111"
end

local function get_colors()
	if not is_custom_theme_active() then
		return nil
	end
	if _cache.colors == nil then
		_cache.colors = require("custom-theme-riii111").palette().lualine
	end
	return _cache.colors
end

vim.api.nvim_create_autocmd("ColorScheme", {
	callback = function()
		_cache.colors = nil
		_file_icon_color_cache = nil
	end,
	group = vim.api.nvim_create_augroup("LualineColorCache", { clear = true }),
})

local icons = {
	git = "",
	question = "",
	term = "",
	floppy = "󰄳",
	treesitter = "",
	ls_inactive = "󰒲 ",
	ls_active = " ",
	lock = "",
	debug = " ",
	code_lens_action = "",
	typos = "󰗊",
}

local diagnostics_icons = {
	Error = "󰅙 ",
	Warn = "⚠ ",
	Info = "󰋽 ",
	Hint = "󰌶 ",
}

local lazy_icons = {
	git = {
		added = "+",
		modified = "~",
		removed = "-",
	},
}

local window_numbers = {
	"󰼏 ",
	"󰼐 ",
	"󰼑 ",
	"󰼒 ",
	"󰼓 ",
	"󰼔 ",
	"󰼕 ",
	"󰼖 ",
	"󰼗 ",
	"󰿪 ",
}

local conditions = {
	buffer_not_empty = function()
		return vim.fn.empty(vim.fn.expand("%:t")) ~= 1
	end,
	hide_in_width = function()
		return vim.fn.winwidth(0) > 80
	end,
	hide_small = function()
		return vim.fn.winwidth(0) > 120
	end,
	check_git_workspace = function()
		local filepath = vim.fn.expand("%:p:h")
		local gitdir = vim.fn.finddir(".git", filepath .. ";")
		return gitdir and #gitdir > 0 and #gitdir < #filepath
	end,
}

-- ============================================================================
-- Utility functions
-- ============================================================================

local function get_file_info()
	return vim.fn.expand("%:t"), vim.fn.expand("%:e")
end

local function get_file_icon()
	local devicons = get_devicons()
	if not devicons then
		return ""
	end
	local f_name, f_extension = get_file_info()
	local icon = devicons.get_icon(f_name, f_extension)
	if icon == nil then
		icon = icons.question
	end
	return icon
end

local function get_file_icon_color()
	local f_name, f_ext = get_file_info()
	local devicons = get_devicons()
	if devicons then
		local icon, iconhl = devicons.get_icon(f_name, f_ext)
		if icon ~= nil then
			return vim.fn.synIDattr(vim.fn.hlID(iconhl), "fg")
		end
	end
	local colors = get_colors()
	return colors and colors.fg or nil
end

-- ============================================================================
-- LSP-related functions
-- ============================================================================

local function lsp_server_icon(name, icon)
	local buf_clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
	if next(buf_clients) == nil then
		return ""
	end
	for _, client in pairs(buf_clients) do
		if client.name == name then
			return icon
		end
	end
	return ""
end

-- ============================================================================
-- UI component functions
-- ============================================================================

local function git()
	local colors = get_colors()
	local component = {
		"b:gitsigns_head",
		icon = icons.git,
		cond = conditions.check_git_workspace,
		padding = { left = 2, right = 2 },
		separator = { right = "" },
	}
	if colors then
		component.color = { fg = colors.fg, bg = colors.git_bg }
	end
	return component
end

local function file_icon()
	local colors = get_colors()
	return {
		function()
			local fi = get_file_icon()
			local new_color = get_file_icon_color()
			if _file_icon_color_cache ~= new_color then
				local hl_opts = { fg = new_color }
				if colors then
					hl_opts.bg = colors.section_c_bg
				end
				vim.api.nvim_set_hl(0, "LualineFileIconColor", hl_opts)
				_file_icon_color_cache = new_color
			end
			if vim.bo.buftype == "terminal" then
				return icons.term
			end
			local winnr = vim.api.nvim_win_get_number(vim.api.nvim_get_current_win())
			if winnr > 10 then
				winnr = 10
			end
			local win = window_numbers[winnr]
			return win .. " " .. fi
		end,
		padding = { left = 1, right = 0 },
		cond = conditions.buffer_not_empty,
		color = "LualineFileIconColor",
		gui = "bold",
	}
end

local function file_name()
	local colors = get_colors()
	local component = {
		function()
			local show_name = vim.fn.expand("%:t")
			local modified = ""
			if vim.bo.modified then
				modified = " " .. icons.floppy
			end
			return show_name .. modified
		end,
		padding = { left = 1, right = 1 },
		cond = conditions.buffer_not_empty,
	}
	if colors then
		component.color = { fg = colors.fg, gui = "bold", bg = colors.section_c_bg }
	end
	return component
end

local function diff()
	local colors = get_colors()
	local component = {
		"diff",
		symbols = {
			added = lazy_icons.git.added,
			modified = lazy_icons.git.modified,
			removed = lazy_icons.git.removed,
		},
		source = function()
			local gitsigns = vim.b.gitsigns_status_dict
			if gitsigns then
				return {
					added = gitsigns.added,
					modified = gitsigns.changed,
					removed = gitsigns.removed,
				}
			end
		end,
	}
	if colors then
		component.diff_color = {
			added = { fg = colors.git.add, bg = colors.section_c_bg },
			modified = { fg = colors.git.change, bg = colors.section_c_bg },
			removed = { fg = colors.git.delete, bg = colors.section_c_bg },
		}
		component.color = { bg = colors.section_c_bg }
	end
	return component
end

local function lazy_status()
	local colors = get_colors()
	local component = {
		function()
			local lazy = get_lazy_status()
			if lazy and lazy.updates then
				return lazy.updates()
			end
			return ""
		end,
		cond = function()
			local lazy = get_lazy_status()
			return lazy and lazy.has_updates and lazy.has_updates()
		end,
	}
	if colors then
		component.color = { fg = colors.orange, bg = colors.section_c_bg }
	end
	return component
end

-- Left arrow separator for Y section start
local function section_separator_left()
	local colors = get_colors()
	local component = {
		function()
			return ""
		end,
		padding = { left = 0, right = 0 },
	}
	if colors then
		component.color = { fg = colors.section_y_bg }
	end
	return component
end

-- Right arrow separator for C section end
local function section_separator_right()
	local colors = get_colors()
	local component = {
		function()
			return ""
		end,
		padding = { left = 0, right = 0 },
	}
	if colors then
		component.color = { fg = colors.section_c_bg }
	end
	return component
end

local function treesitter()
	local colors = get_colors()
	local component = {
		function()
			local ts_parsers = get_treesitter_parsers()
			if ts_parsers then
				local buf = vim.api.nvim_get_current_buf()
				local lang = ts_parsers.get_buf_lang(buf)
				if lang then
					return icons.treesitter
				end
			end
			return ""
		end,
		padding = 0,
		cond = conditions.hide_small,
	}
	if colors then
		component.color = { fg = colors.green }
	end
	return component
end

local function file_size()
	local colors = get_colors()
	local component = {
		function()
			local file = vim.fn.expand("%:p")
			if string.len(file) == 0 then
				return ""
			end
			local size = vim.fn.getfsize(file)
			if size <= 0 then
				return ""
			end
			local sufixes = { "b", "k", "m", "g" }
			local i = 1
			while size > 1024 do
				size = size / 1024
				i = i + 1
			end
			return string.format("%.1f%s", size, sufixes[i])
		end,
		cond = conditions.buffer_not_empty,
	}
	if colors then
		component.color = { fg = colors.fg }
	end
	return component
end

local function file_format()
	local colors = get_colors()
	local component = {
		"fileformat",
		fmt = string.upper,
		icons_enabled = true,
		cond = conditions.hide_in_width,
	}
	if colors then
		component.color = { fg = colors.green, gui = "bold" }
	end
	return component
end

local function get_lsp_client_names(buf_clients)
	local client_names = {}
	for _, client in pairs(buf_clients) do
		if not (client.name == "null-ls" or client.name == "typos_lsp" or client.name == "harper_ls") then
			table.insert(client_names, client.name)
		end
	end
	return client_names
end

local function lsp_servers()
	local colors = get_colors()
	local component = {
		function()
			local buf_clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
			if next(buf_clients) == nil then
				return icons.ls_inactive .. "none"
			end

			local all_names = get_lsp_client_names(buf_clients)

			if #all_names == 0 then
				return icons.ls_inactive .. "none"
			else
				return icons.ls_active .. table.concat(all_names, " ")
			end
		end,
		cond = conditions.hide_in_width,
	}
	if colors then
		component.color = { fg = colors.fg }
	end
	return component
end

local function location()
	local colors = get_colors()
	local component = {
		"location",
		padding = 0,
	}
	if colors then
		component.color = { fg = colors.orange }
	end
	return component
end

local function current_time()
	local colors = get_colors()
	local component = {
		function()
			return os.date("%H:%M")
		end,
		icon = "󰥔",
		separator = { right = "" },
	}
	if colors then
		component.color = { fg = colors.cyan }
	end
	return component
end

local function file_read_only()
	local colors = get_colors()
	local component = {
		function()
			if not vim.bo.readonly or not vim.bo.modifiable then
				return ""
			end
			return string.gsub(icons.lock, "%s+", "")
		end,
	}
	if colors then
		component.color = { fg = colors.red }
	end
	return component
end

local function diagnostic_ok()
	local colors = get_colors()
	local component = {
		function()
			local diagnostics_list = vim.diagnostic.get(0)
			if #diagnostics_list == 0 then
				return "󰸞"
			else
				return ""
			end
		end,
		cond = conditions.hide_in_width,
		padding = { left = 2, right = 0 },
	}
	if colors then
		component.color = { fg = colors.green }
	end
	return component
end

local function diagnostics()
	local colors = get_colors()
	local component = {
		"diagnostics",
		sources = { "nvim_diagnostic" },
		symbols = {
			error = diagnostics_icons.Error,
			warn = diagnostics_icons.Warn,
			info = diagnostics_icons.Info,
			hint = diagnostics_icons.Hint,
		},
		cond = function()
			local diagnostics_list = vim.diagnostic.get(0)
			return #diagnostics_list > 0 and conditions.hide_in_width()
		end,
	}
	if colors then
		component.diagnostics_color = {
			error = { fg = colors.red },
			warn = { fg = colors.yellow },
			info = { fg = colors.blue },
			hint = { fg = colors.cyan },
		}
	end
	return component
end

local function dap_status()
	local colors = get_colors()
	local component = {
		function()
			local dap = get_dap()
			if dap and dap.status then
				local status = dap.status()
				if status ~= "" then
					return icons.debug .. status
				end
			end
			return ""
		end,
		cond = function()
			local dap = get_dap()
			return dap and dap.status and dap.status() ~= ""
		end,
	}
	if colors then
		component.color = { fg = colors.red }
	end
	return component
end

local function space()
	return {
		function()
			return " "
		end,
		padding = 0,
		cond = conditions.hide_in_width,
	}
end

local function null_ls()
	local colors = get_colors()
	local component = {
		function()
			return lsp_server_icon("null-ls", icons.code_lens_action)
		end,
		padding = 0,
		cond = conditions.hide_small,
	}
	if colors then
		component.color = { fg = colors.blue }
	end
	return component
end

local function grammar_lsp(server_name)
	local colors = get_colors()
	local component = {
		function()
			return lsp_server_icon(server_name, icons.typos)
		end,
		padding = 0,
		cond = conditions.hide_small,
	}
	if colors then
		component.color = { fg = colors.yellow }
	end
	return component
end

local function typos_lsp()
	return grammar_lsp("typos_lsp")
end

local function harper_ls()
	return grammar_lsp("harper_ls")
end

local function get_lualine_theme()
	if not is_custom_theme_active() then
		return "auto"
	end
	local colors = get_colors()
	return {
		normal = {
			a = { fg = colors.normal_a, bg = colors.mode_normal, gui = "bold" },
			b = { fg = colors.normal_b, bg = colors.normal_bg_b },
			c = { fg = colors.normal_c },
			x = { fg = colors.normal_c },
			y = { fg = colors.normal_b, bg = colors.normal_bg_b },
			z = { fg = colors.normal_b, bg = colors.normal_bg_b },
		},
		insert = {
			a = { fg = colors.normal_a, bg = colors.mode_insert, gui = "bold" },
			b = { fg = colors.normal_b, bg = colors.normal_bg_b },
			c = { fg = colors.normal_c },
			x = { fg = colors.normal_c },
			y = { fg = colors.normal_b, bg = colors.normal_bg_b },
			z = { fg = colors.normal_b, bg = colors.normal_bg_b },
		},
		visual = {
			a = { fg = colors.normal_a, bg = colors.mode_visual, gui = "bold" },
			b = { fg = colors.normal_b, bg = colors.normal_bg_b },
			c = { fg = colors.normal_c },
			x = { fg = colors.normal_c },
			y = { fg = colors.normal_b, bg = colors.normal_bg_b },
			z = { fg = colors.normal_b, bg = colors.normal_bg_b },
		},
		replace = {
			a = { fg = colors.fg, bg = colors.mode_replace, gui = "bold" },
			b = { fg = colors.normal_b, bg = colors.normal_bg_b },
			c = { fg = colors.normal_c },
			x = { fg = colors.normal_c },
			y = { fg = colors.normal_b, bg = colors.normal_bg_b },
			z = { fg = colors.normal_b, bg = colors.normal_bg_b },
		},
		command = {
			a = { fg = colors.normal_a, bg = colors.mode_command, gui = "bold" },
			b = { fg = colors.normal_b, bg = colors.normal_bg_b },
			c = { fg = colors.normal_c },
			x = { fg = colors.normal_c },
			y = { fg = colors.normal_b, bg = colors.normal_bg_b },
			z = { fg = colors.normal_b, bg = colors.normal_bg_b },
		},
		terminal = {
			a = { fg = colors.normal_a, bg = colors.mode_insert, gui = "bold" },
			b = { fg = colors.normal_b, bg = colors.normal_bg_b },
			c = { fg = colors.normal_c },
			x = { fg = colors.normal_c },
			y = { fg = colors.normal_b, bg = colors.normal_bg_b },
			z = { fg = colors.normal_b, bg = colors.normal_bg_b },
		},
	}
end

return {
	"nvim-lualine/lualine.nvim",
	config = function()
		require("lualine").setup({
			options = {
				theme = get_lualine_theme(),
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
				always_divide_middle = true,
			},
			sections = {
				lualine_a = {
					{
						"mode",
						fmt = function(str)
							return str
						end,
						separator = { left = "", right = "" },
					},
				},
				lualine_b = {
					git(),
				},
				lualine_c = {
					file_icon(),
					file_name(),
					diff(),
					lazy_status(),
					section_separator_right(),
				},
				lualine_x = {
					section_separator_left(),
				},
				lualine_y = {
					diagnostic_ok(),
					diagnostics(),
					space(),
					dap_status(),
					treesitter(),
					typos_lsp(),
					harper_ls(),
					null_ls(),
					lsp_servers(),
				},
				lualine_z = {
					location(),
					current_time(),
				},
			},
		})

		-- Refresh lualine when colorscheme changes
		vim.api.nvim_create_autocmd("ColorScheme", {
			callback = function()
				_cache.colors = nil
				_file_icon_color_cache = nil
				require("lualine").setup({
					options = {
						theme = get_lualine_theme(),
					},
				})
			end,
			group = vim.api.nvim_create_augroup("LualineThemeRefresh", { clear = true }),
		})
	end,
}
