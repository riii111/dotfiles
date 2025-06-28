-- Define colors and icons locally to avoid dependencies
local colors = {
    bg = "#24283b",
    fg = "#c0caf5",
    yellow = "#e0af68",
    cyan = "#7dcfff",
    green = "#9ece6a",
    orange = "#ff9e64",
    violet = "#9d7cd8",
    magenta = "#bb9af7",
    blue = "#7aa2f7",
    red = "#f7768e",
    git = {
        add = "#9ece6a",
        change = "#e0af68",
        delete = "#f7768e",
    },
}

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
    Error = "󰅚 ",
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

local file_icons = {}

local mode_icons = {
    n = " ",
    i = " ",
    v = " ",
    c = " ",
    r = " ",
    R = " ",
    d = " ",
}

-- Check for null-ls availability
local has_nls, nls = pcall(require, "null-ls")

local file_icon_colors = {
    Brown = "#905532",
    Aqua = "#3AFFDB",
    Blue = "#689FB6",
    DarkBlue = "#44788E",
    Purple = "#834F79",
    Red = "#AE403F",
    Beige = "#F5C06F",
    Yellow = "#F09F17",
    Orange = "#D4843E",
    DarkOrange = "#F16529",
    Pink = "#CB6F6F",
    Salmon = "#EE6E73",
    Green = "#8FAA54",
    LightGreen = "#31B53E",
    White = "#FFFFFF",
    LightBlue = "#5fd7ff",
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

local mode_color = {
    n = colors.git.delete,
    i = colors.green,
    v = colors.yellow,
    [""] = colors.blue,
    V = colors.yellow,
    c = colors.cyan,
    no = colors.magenta,
    s = colors.orange,
    S = colors.orange,
    [""] = colors.orange,
    ic = colors.yellow,
    R = colors.violet,
    Rv = colors.violet,
    cv = colors.red,
    ce = colors.red,
    r = colors.cyan,
    rm = colors.cyan,
    ["r?"] = colors.cyan,
    ["!"] = colors.red,
    t = colors.red,
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

local function get_file_info()
    return vim.fn.expand("%:t"), vim.fn.expand("%:e")
end

local function get_file_icon()
    local icon
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if not ok then
        print("No icon plugin found. Please install 'kyazdani42/nvim-web-devicons'")
        return ""
    end
    local f_name, f_extension = get_file_info()
    icon = devicons.get_icon(f_name, f_extension)
    if icon == nil then
        icon = icons.question
    end
    return icon
end

local function get_file_icon_color(file_icon)
    local f_name, f_ext = get_file_info()
    local has_devicons, devicons = pcall(require, "nvim-web-devicons")
    if has_devicons then
        local icon, iconhl = devicons.get_icon(f_name, f_ext)
        if icon ~= nil then
            return vim.fn.synIDattr(vim.fn.hlID(iconhl), "fg")
        end
    end

    local icon = file_icon:match("%S+")
    for k, _ in pairs(file_icons) do
        if vim.fn.index(file_icons[k], icon) ~= -1 then
            return file_icon_colors[k]
        end
    end
end

local function list_nls_providers(filetype)
    if not has_nls then
        return {}
    end
    local ok, sources = pcall(require, "null-ls.sources")
    if not ok then
        return {}
    end
    local available_sources = sources.get_available(filetype)
    local registered = {}
    for _, source in ipairs(available_sources) do
        for method in pairs(source.methods) do
            registered[method] = registered[method] or {}
            table.insert(registered[method], source.name)
        end
    end
    return registered
end

local function list_registered_formatters(filetype)
    if not has_nls then
        return {}
    end
    local registered_providers = list_nls_providers(filetype)
    return registered_providers[nls.methods.FORMATTING] or {}
end

local function list_registered_linters(filetype)
    if not has_nls then
        return {}
    end
    local registered_providers = list_nls_providers(filetype)
    local providers_for_methods = vim.iter(vim.tbl_map(function(m)
        return registered_providers[m] or {}
    end, {
        nls.methods.DIAGNOSTICS,
        nls.methods.DIAGNOSTICS_ON_OPEN,
        nls.methods.DIAGNOSTICS_ON_SAVE,
    }))
        :flatten()
        :totable()

    return providers_for_methods
end

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

local function vim_mode()
    return {
        function()
            local mod = vim.fn.mode()
            if mod == "n" or mod == "no" or mod == "nov" then
                return mode_icons.n
            elseif mod == "i" or mod == "ic" or mod == "ix" then
                return mode_icons.i
            elseif mod == "V" or mod == "v" or mod == "vs" or mod == "Vs" or mod == "cv" then
                return mode_icons.v
            elseif mod == "c" or mod == "ce" then
                return mode_icons.c
            elseif mod == "r" or mod == "rm" or mod == "r?" then
                return mode_icons.r
            elseif mod == "R" or mod == "Rc" or mod == "Rv" or mod == "Rv" then
                return mode_icons.R
            else
                return mode_icons.d
            end
        end,
        padding = { left = 1, right = 0 },
    }
end

local function git()
    return {
        "b:gitsigns_head",
        icon = " " .. icons.git,
        cond = conditions.check_git_workspace,
        color = { fg = colors.blue, bg = colors.bg },
        padding = 0,
    }
end

local function file_icon()
    return {
        function()
            local fi = get_file_icon()
            vim.api.nvim_command("hi! LualineFileIconColor guifg=" .. get_file_icon_color(fi) .. " guibg=" .. colors.bg)
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
        padding = { left = 2, right = 0 },
        cond = conditions.buffer_not_empty,
        color = "LualineFileIconColor",
        gui = "bold",
    }
end

local function file_name()
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
        color = { fg = colors.fg, gui = "bold", bg = colors.bg },
        cond = conditions.buffer_not_empty,
    }
end

local function diff()
    return {
        "diff",
        symbols = {
            added = lazy_icons.git.added,
            modified = lazy_icons.git.modified,
            removed = lazy_icons.git.removed,
        },
        diff_color = {
            added = { fg = colors.git.add, bg = colors.bg },
            modified = { fg = colors.git.change, bg = colors.bg },
            removed = { fg = colors.git.delete, bg = colors.bg },
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
    return {
        function()
            local ok, lazy = pcall(require, "lazy.status")
            if ok and lazy.updates then
                return lazy.updates()
            end
            return ""
        end,
        cond = function()
            local ok, lazy = pcall(require, "lazy.status")
            return ok and lazy.has_updates and lazy.has_updates()
        end,
        color = { fg = colors.orange, bg = colors.bg },
    }
end

local function circle_icon(direction)
    return {
        function()
            if direction == "left" then
                return icons.circle_left
            else
                return icons.circle_right
            end
        end,
        padding = { left = 0, right = 0 },
        color = { fg = colors.bg },
    }
end

local function treesitter()
    return {
        function()
            local ok, ts = pcall(require, "nvim-treesitter.parsers")
            if ok then
                local buf = vim.api.nvim_get_current_buf()
                local lang = ts.get_buf_lang(buf)
                if lang then
                    return icons.treesitter
                end
            end
            return ""
        end,
        padding = 0,
        color = { fg = colors.green, bg = colors.bg },
        cond = conditions.hide_in_width,
    }
end

local function file_size()
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

        color = { fg = colors.fg, bg = colors.bg },
        cond = conditions.buffer_not_empty,
    }
end

local function file_format()
    return {
        "fileformat",
        fmt = string.upper,
        icons_enabled = true,
        color = { fg = colors.green, gui = "bold", bg = colors.bg },
        cond = conditions.hide_in_width,
    }
end

local function lsp_servers()
    return {
        function()
            local buf_clients = vim.lsp.get_clients({ bufnr = vim.api.nvim_get_current_buf() })
            if next(buf_clients) == nil then
                return icons.ls_inactive .. "none"
            end
            local buf_ft = vim.bo.filetype
            local buf_client_names = {}
            local trim_width = 100
            local trim = vim.fn.winwidth(0) < trim_width

            for _, client in pairs(buf_clients) do
                if not (client.name == "null-ls" or client.name == "typos_lsp" or client.name == "harper_ls") then
                    local _added_client = client.name
                    if trim then
                        _added_client = string.sub(client.name, 1, 4)
                    end
                    table.insert(buf_client_names, _added_client)
                end
            end

            -- add formatter
            for _, fmt in pairs(list_registered_formatters(buf_ft)) do
                local _added_formatter = fmt
                if trim then
                    _added_formatter = string.sub(fmt, 1, 4)
                end
                table.insert(buf_client_names, _added_formatter)
            end

            -- add linter
            for _, lnt in pairs(list_registered_linters(buf_ft)) do
                local _added_linter = lnt
                if trim then
                    _added_linter = string.sub(lnt, 1, 4)
                end
                table.insert(buf_client_names, _added_linter)
            end

            if #buf_client_names == 0 then
                return icons.ls_inactive .. "none"
            else
                return icons.ls_active .. table.concat(buf_client_names, " ")
            end
        end,
        color = { fg = colors.fg, bg = colors.bg },
        cond = conditions.hide_in_width,
    }
end

local function location()
    return {
        "location",
        padding = 0,
        color = { fg = colors.orange, bg = colors.bg },
    }
end

local function file_position()
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
        color = { fg = colors.yellow, bg = colors.bg },
    }
end

local function file_read_only()
    return {
        function()
            if not vim.bo.readonly or not vim.bo.modifiable then
                return ""
            end
            return string.gsub(icons.lock, "%s+", "")
        end,
        color = { fg = colors.red, bg = colors.bg },
    }
end

local function diagnostic_ok()
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
        color = { fg = colors.green, bg = colors.bg },
    }
end

local function diagnostics()
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
            error = { fg = colors.red, bg = colors.bg },
            warn = { fg = colors.yellow, bg = colors.bg },
            info = { fg = colors.blue, bg = colors.bg },
            hint = { fg = colors.cyan, bg = colors.bg },
        },
        color = { bg = colors.bg },
        cond = function()
            local diagnostics_list = vim.diagnostic.get(0)
            return #diagnostics_list > 0 and conditions.hide_in_width()
        end,
    }
end

local function dap_status()
    return {
        function()
            local ok, dap = pcall(require, "dap")
            if ok and dap.status then
                local status = dap.status()
                if status ~= "" then
                    return icons.debug .. status
                end
            end
            return ""
        end,
        cond = function()
            return package.loaded["dap"] and require("dap").status and require("dap").status() ~= ""
        end,
        color = { fg = colors.red, bg = colors.bg },
    }
end

local function space()
    return {
        function()
            return " "
        end,
        padding = 0,
        color = { fg = colors.blue, bg = colors.bg },
        cond = conditions.hide_in_width,
    }
end

local function null_ls()
    return {
        function()
            return lsp_server_icon("null-ls", icons.code_lens_action)
        end,
        padding = 0,
        color = { fg = colors.blue, bg = colors.bg },
        cond = conditions.hide_in_width,
    }
end

local function typos_lsp()
    return {
        function()
            return lsp_server_icon("typos_lsp", icons.typos)
        end,
        padding = 0,
        color = { fg = colors.yellow, bg = colors.bg },
        cond = conditions.hide_in_width,
    }
end

local function harper_ls()
    return {
        function()
            return lsp_server_icon("harper_ls", icons.typos)
        end,
        padding = 0,
        color = { fg = colors.yellow, bg = colors.bg },
        cond = conditions.hide_in_width,
    }
end

local custom_theme = {
    normal = {
        a = { fg = "#1a1e29", bg = "#7aa2f7", gui = "bold" }, -- Blue for normal
        b = { fg = "#e9dbdb", bg = "#22252f" },
        c = { fg = "#e9dbdb", bg = "#16181f" }, -- Darker background for center
        x = { fg = "#e9dbdb", bg = "#16181f" },
        y = { fg = "#e9dbdb", bg = "#22252f" },
        z = { fg = "#1a1e29", bg = "#7aa2f7", gui = "bold" },
    },
    insert = {
        a = { fg = "#1a1e29", bg = "#9ece6a", gui = "bold" }, -- Green for insert
        b = { fg = "#e9dbdb", bg = "#22252f" },
        c = { fg = "#e9dbdb", bg = "#16181f" },
        x = { fg = "#e9dbdb", bg = "#16181f" },
        y = { fg = "#e9dbdb", bg = "#22252f" },
        z = { fg = "#1a1e29", bg = "#9ece6a", gui = "bold" },
    },
    visual = {
        a = { fg = "#1a1e29", bg = "#bb9af7", gui = "bold" }, -- Purple for visual
        b = { fg = "#e9dbdb", bg = "#22252f" },
        c = { fg = "#e9dbdb", bg = "#16181f" },
        x = { fg = "#e9dbdb", bg = "#16181f" },
        y = { fg = "#e9dbdb", bg = "#22252f" },
        z = { fg = "#1a1e29", bg = "#bb9af7", gui = "bold" },
    },
    replace = {
        a = { fg = "#ffffff", bg = "#f7768e", gui = "bold" }, -- Red for replace
        b = { fg = "#e9dbdb", bg = "#22252f" },
        c = { fg = "#e9dbdb", bg = "#16181f" },
        x = { fg = "#e9dbdb", bg = "#16181f" },
        y = { fg = "#e9dbdb", bg = "#22252f" },
        z = { fg = "#ffffff", bg = "#f7768e", gui = "bold" },
    },
    command = {
        a = { fg = "#1a1e29", bg = "#e0af68", gui = "bold" }, -- Yellow for command
        b = { fg = "#e9dbdb", bg = "#22252f" },
        c = { fg = "#e9dbdb", bg = "#16181f" },
        x = { fg = "#e9dbdb", bg = "#16181f" },
        y = { fg = "#e9dbdb", bg = "#22252f" },
        z = { fg = "#1a1e29", bg = "#e0af68", gui = "bold" },
    },
}

return {
    "nvim-lualine/lualine.nvim",
    opts = {
        options = {
            theme = custom_theme,
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
    },
}
