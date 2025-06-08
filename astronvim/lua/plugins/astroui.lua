-- AstroUI provides the basis for configuring the AstroNvim User Interface
-- Configuration documentation can be found with `:h astroui`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astroui",
  ---@type AstroUIOpts
  opts = {
    -- Let astroui use its default colorscheme (likely astrodark)
    -- colorscheme = "flate_arc_italic", -- Commented out
    highlights = {
      -- Clear highlights.init as we will apply them in user.flate_arc_italic.lua
      init = {},
      astrodark = {
        -- Example: Normal = { bg = "#000000" },
      },
    },
    -- Icons can be configured throughout the interface
    icons = {
      -- LSP診断アイコン
      diagnostics = {
        Error = "󰅚 ",
        Warn = "󰀪 ",
        Info = "󰋽 ",
        Hint = "󰌶 ",
      },
      -- LSPのロード状態表示
      LSPLoading1 = "⠋",
      LSPLoading2 = "⠙",
      LSPLoading3 = "⠹",
      LSPLoading4 = "⠸",
      LSPLoading5 = "⠼",
      LSPLoading6 = "⠴",
      LSPLoading7 = "⠦",
      LSPLoading8 = "⠧",
      LSPLoading9 = "⠇",
      LSPLoading10 = "⠏",
    },
  },
}
