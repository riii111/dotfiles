return {
  -- Mason tool installer
  {
    "williamboman/mason.nvim",
    priority = 100,
    config = function()
      require("mason").setup()
    end,
  },


  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    priority = 80,
    opts = {
      ensure_installed = {
        -- LSP servers
        "lua-language-server",
        "typescript-language-server", -- ts_ls用
        "sqls",

        -- Formatters
        "stylua",
        "goimports",
        "sql-formatter",

        -- Linters
        "golangci-lint",

        -- Debuggers  
        "debugpy",
        "delve",

        -- Other tools
        "tree-sitter-cli",
      },
      -- Auto update tools
      auto_update = true,
      run_on_start = true,
      -- Disable automatic integration that causes conflicts
      integrations = {
        ["mason-lspconfig"] = false,
      },
    },
  },
}
