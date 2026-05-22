return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      return require("utils.treesitter").extend(opts, {
        languages = { "zig" },
        filetypes = { "zig", "zir", "zon" },
        indent_filetypes = { "zig", "zir", "zon" },
      })
    end,
  },

  {
    name = "zig-lsp-setup",
    dir = vim.fn.stdpath("config") .. "/lua/plugins/languages",
    lazy = false,
    dependencies = {
      "neovim/nvim-lspconfig",
    },
    config = function()
      vim.filetype.add({
        extension = {
          zon = "zon",
          zir = "zir",
        },
      })

      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[bufnr].filetype == "" then
          local filetype = vim.filetype.match({ filename = vim.api.nvim_buf_get_name(bufnr) })
          if filetype == "zig" or filetype == "zir" or filetype == "zon" then
            vim.bo[bufnr].filetype = filetype
          end
        end
      end

      vim.treesitter.language.register("zig", { "zir", "zon" })

      vim.lsp.config("zls", {
        cmd = { "zls" },
        filetypes = { "zig", "zir", "zon" },
        root_markers = { "zls.json", "build.zig", ".git" },
      })

      local function start_zls(bufnr)
        local filetype = vim.bo[bufnr].filetype
        if filetype == "zig" or filetype == "zir" or filetype == "zon" then
          if #vim.lsp.get_clients({ bufnr = bufnr, name = "zls" }) == 0 then
            vim.lsp.start(vim.lsp.config.zls, { bufnr = bufnr })
          end
        end
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "zig", "zir", "zon" },
        callback = function(args)
          start_zls(args.buf)
        end,
      })

      vim.schedule(function()
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
          start_zls(bufnr)
        end
      end)
    end,
  },
}
