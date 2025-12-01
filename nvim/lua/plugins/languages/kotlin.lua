return {
  -- Treesitter support for Kotlin
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts = opts or {}
      local ensure = opts.ensure_installed or {}
      if not vim.tbl_contains(ensure, "kotlin") then
        table.insert(ensure, "kotlin")
      end
      opts.ensure_installed = ensure
      return opts
    end,
  },

  -- Kotlin LSP configuration (riii111/kotlin-language-server fork)
  -- NOTE: Using a wrapper plugin instead of extending "neovim/nvim-lspconfig" directly
  --       because lazy.nvim may skip this config function when lspconfig is already loaded
  --       by plugins/lsp.lua. A separate plugin name ensures this config always runs.
  --
  -- SETUP: Using forked kotlin-language-server with fixes for generated code (e.g., jOOQ) definition jump.
  --        The fork is built locally and symlinked to ~/.local/bin/kotlin-language-server
  --        See: https://github.com/riii111/kotlin-language-server
  --        Build: cd <fork-repo> && ./gradlew :server:installDist
  --        Symlink: ln -sf <fork-repo>/server/build/install/server/bin/kotlin-language-server ~/.local/bin/
  {
    name = "kotlin-lsp-setup",
    dir = vim.fn.stdpath("config"),
    ft = { "kotlin" },
    dependencies = { "neovim/nvim-lspconfig" },
    config = function()
      local java_home = vim.env.JAVA_HOME
      local kotlin_cmd = { "kotlin-language-server" } -- Uses ~/.local/bin symlink (fork) or falls back to PATH

      vim.lsp.config("kotlin_lsp", {
        cmd = kotlin_cmd,
        cmd_env = {
          JAVA_HOME = java_home,
          JDK_HOME = java_home,
          PATH = (java_home and (java_home .. "/bin:" .. vim.env.PATH)) or vim.env.PATH,
        },
        filetypes = { "kotlin" },
        root_markers = {
          "settings.gradle.kts",
          "settings.gradle",
          "build.gradle.kts",
          "build.gradle",
          ".git",
        },
        settings = {
          kotlin = {
            diagnostics = {
              debounceTime = 400,
            },
            indexing = {
              enabled = false,
            },
          },
        },
      })

      vim.lsp.enable("kotlin_lsp")

      -- Keymaps (IntelliJ-like actions)
      local ok, lsp_actions = pcall(require, "utils.lsp-actions")
      if ok then
        vim.api.nvim_create_autocmd("FileType", {
          pattern = "kotlin",
          callback = function()
            local opts = { buffer = true, silent = true }
            vim.keymap.set("n", "<M-CR>", lsp_actions.language_specific_code_action, opts)
            vim.keymap.set("n", "<D-S-r>", lsp_actions.kotlin_refactor_menu, opts)
            vim.keymap.set("n", "<M-S-r>", lsp_actions.kotlin_refactor_menu, opts)
          end,
        })
      end
    end,
  },

  -- Formatting and linting with ktlint (autocmd only; sources are in plugins/lsp.lua)
  {
    "nvimtools/none-ls.nvim",
    ft = { "kotlin" },
    config = function()
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = { "*.kt", "*.kts" },
        callback = function()
          vim.lsp.buf.format({
            filter = function(client)
              return client.name == "null-ls"
            end,
            timeout_ms = 5000,
          })
        end,
      })
    end,
  },
}
