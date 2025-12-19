-- Lazy-loaded module cache (populated on first use)
local _cache = {}
local _file_icon_color_cache = nil

local function get_devicons()
	if _cache.devicons == nil then
		local ok, mod = pcall(require, "nvim-web-devicons")
		_cache.devicons = ok and mod or false
	end
	return _cache.devicons
end

local function get_lazy_status()
	if _cache.lazy_status == nil then
		local ok, mod = pcall(require, "lazy.status")
		_cache.lazy_status = ok and mod or false
	end
	return _cache.lazy_status
end

local function get_treesitter_parsers()
	if _cache.ts_parsers == nil then
		local ok, mod = pcall(require, "nvim-treesitter.parsers")
		_cache.ts_parsers = ok and mod or false
	end
	return _cache.ts_parsers
end

local function get_dap()
	if _cache.dap == nil then
		local ok, mod = pcall(require, "dap")
		_cache.dap = ok and mod or false
	end
	return _cache.dap
end

local function get_colors()
	if _cache.colors == nil then
		_cache.colors = require("config.colors").lualine
	end
	return _cache.colors
end

local icons = {
	git = "",
	question = "",
	term = "",
	floppy = "󰄳",
	circle_left = "",
	circle_right = "",
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
		added = " ",
		modified = " ",
		removed = " ",
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
	return get_colors().fg
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
	return {
		"b:gitsigns_head",
		icon = icons.git,
		cond = conditions.check_git_workspace,
		color = { fg = colors.magenta, bg = colors.bubble_branch },
		padding = { left = 2, right = 2 },
		separator = { right = "" },
	}
end

local function file_icon()
	local colors = get_colors()
	return {
		function()
			local fi = get_file_icon()
			local new_color = get_file_icon_color()
			if _file_icon_color_cache ~= new_color then
				vim.api.nvim_command("hi! LualineFileIconColor guifg=" .. new_color .. " guibg=" .. colors.bubble_file)
				_file_icon_color_cache = new_color
			end
			local fname = vim.fn.expand("%:p")
			if string.find(fname, "term://") ~= nil then
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
	return {
		function()
			local show_name = vim.fn.expand("%:t")
			local modified = ""
			if vim.bo.modified then
				modified = " " .. icons.floppy
			end
			return show_name .. modified
		end,
		padding = { left = 1, right = 1 },
		color = { fg = colors.fg, gui = "bold", bg = colors.bubble_file },
		cond = conditions.buffer_not_empty,
		separator = { right = "" },
	}
end

local function diff()
	local colors = get_colors()
	return {
		"diff",
		symbols = {
			added = lazy_icons.git.added,
			modified = lazy_icons.git.modified,
			removed = lazy_icons.git.removed,
		},
		diff_color = {
			added = { fg = colors.git.add },
			modified = { fg = colors.git.change },
			removed = { fg = colors.git.delete },
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
end

local function lazy_status()
	local colors = get_colors()
	return {
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
		color = { fg = colors.orange },
	}
end

local function circle_icon(direction)
	local colors = get_colors()
	if direction == "left" then
		return {
			function()
				return ""
			end,
			padding = { left = 0, right = 0 },
			color = { fg = colors.normal_bg_b },
		}
	else
		return {
			function()
				return icons.circle_right
			end,
			padding = { left = 0, right = 0 },
			color = { fg = colors.bubble_file },
		}
	end
end

local function treesitter()
	local colors = get_colors()
	return {
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
		color = { fg = colors.green },
		cond = conditions.hide_in_width,
	}
end

local function file_size()
	local colors = get_colors()
	return {
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
		color = { fg = colors.fg },
		cond = conditions.buffer_not_empty,
	}
end

local function file_format()
	local colors = get_colors()
	return {
		"fileformat",
		fmt = string.upper,
		icons_enabled = true,
		color = { fg = colors.green, gui = "bold" },
		cond = conditions.hide_in_width,
	}
end

local function format_client_name(name, should_trim)
	if should_trim then
		return string.sub(name, 1, 4)
	end
	return name
end

local function get_lsp_client_names(buf_clients, should_trim)
	local client_names = {}
	for _, client in pairs(buf_clients) do
		if not (client.name == "null-ls" or client.name == "typos_lsp" or client.name == "harper_ls") then
			local formatted_name = format_client_name(client.name, should_trim)
			table.insert(client_names, formatted_name)
		end
	end
	return client_names
end

local function lsp_servers()
	local colors = get_colors()
	return {
		function()
			local buf_clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
			if next(buf_clients) == nil then
				return icons.ls_inactive .. "none"
			end

			local should_trim = vim.fn.winwidth(0) < 100
			local all_names = {}

			vim.list_extend(all_names, get_lsp_client_names(buf_clients, should_trim))

			if #all_names == 0 then
				return icons.ls_inactive .. "none"
			else
				return icons.ls_active .. table.concat(all_names, " ")
			end
		end,
		color = { fg = colors.fg },
		cond = conditions.hide_in_width,
	}
end

local function location()
	local colors = get_colors()
	return {
		"location",
		padding = 0,
		color = { fg = colors.orange },
	}
end

local function file_position()
	local colors = get_colors()
	return {
		function()
			local current_line = vim.fn.line(".")
			local total_lines = vim.fn.line("$")
			local chars = { "__", "▁▁", "▂▂", "▃▃", "▄▄", "▅▅", "▆▆", "▇▇", "██" }
			local line_ratio = current_line / total_lines
			local index = math.ceil(line_ratio * #chars)
			return chars[index]
		end,
		padding = 0,
		color = { fg = colors.yellow },
		separator = { right = "" },
	}
end

local function file_read_only()
	local colors = get_colors()
	return {
		function()
			if not vim.bo.readonly or not vim.bo.modifiable then
				return ""
			end
			return string.gsub(icons.lock, "%s+", "")
		end,
		color = { fg = colors.red },
	}
end

local function diagnostic_ok()
	local colors = get_colors()
	return {
		function()
			local diagnostics_list = vim.diagnostic.get(0)
			if #diagnostics_list == 0 then
				return "󰸞"
			else
				return ""
			end
		end,
		cond = conditions.hide_in_width,
		color = { fg = colors.green },
		left_padding = 2,
	}
end

local function diagnostics()
	local colors = get_colors()
	return {
		"diagnostics",
		sources = { "nvim_diagnostic" },
		symbols = {
			error = diagnostics_icons.Error,
			warn = diagnostics_icons.Warn,
			info = diagnostics_icons.Info,
			hint = diagnostics_icons.Hint,
		},
		diagnostics_color = {
			error = { fg = colors.red },
			warn = { fg = colors.yellow },
			info = { fg = colors.blue },
			hint = { fg = colors.cyan },
		},
		cond = function()
			local diagnostics_list = vim.diagnostic.get(0)
			return #diagnostics_list > 0 and conditions.hide_in_width()
		end,
	}
end

local function dap_status()
	local colors = get_colors()
	return {
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
		color = { fg = colors.red },
	}
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
	return {
		function()
			return lsp_server_icon("null-ls", icons.code_lens_action)
		end,
		padding = 0,
		color = { fg = colors.blue },
		cond = conditions.hide_in_width,
	}
end

local function grammar_lsp(server_name)
	local colors = get_colors()
	return {
		function()
			return lsp_server_icon(server_name, icons.typos)
		end,
		padding = 0,
		color = { fg = colors.yellow },
		cond = conditions.hide_in_width,
	}
end

local function typos_lsp()
	return grammar_lsp("typos_lsp")
end

local function harper_ls()
	return grammar_lsp("harper_ls")
end

-- ============================================================================
-- Theme definition
-- ============================================================================

local function get_custom_theme()
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
	}
end

-- ============================================================================
-- Plugin configuration
-- ============================================================================

return {
	"nvim-lualine/lualine.nvim",
	config = function()
		require("lualine").setup({
			options = {
				theme = get_custom_theme(),
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
					circle_icon("right"),
				},
				lualine_x = {
					circle_icon("left"),
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
					space(),
					location(),
					file_size(),
					file_read_only(),
					file_format(),
					file_position(),
				},
			},
		})
	end,
}
