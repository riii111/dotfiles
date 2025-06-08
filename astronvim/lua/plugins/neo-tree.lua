return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      follow_current_file = {
        enabled = true,
        leave_dirs_open = true,
      },
      hijack_netrw_behavior = "open_current",
      use_libuv_file_watcher = true,
      filtered_items = {
        visible = false,
        show_hidden_count = true,
        hide_dotfiles = false,
        hide_gitignored = false,
        hide_by_name = {
          "node_modules",
          "thumbs.db",
        },
        never_show = {
          ".git",
          ".DS_Store",
          ".history",
        },
      },
    },
    default_component_configs = {
      icon = {
        folder_closed = "",
        folder_open = "",
        folder_empty = "",
        default = "",
        highlight = "NeoTreeFileIcon",
      },
    },
    event_handlers = {
      {
        event = "BufEnter",
        handler = function(bufnr)
          if vim.bo[bufnr].filetype == "neo-tree" then return end

          -- 選択したファイルをハイライト表示
          pcall(function()
            local api = require "neo-tree.api"
            local node = api.tree.get_node_by_path(vim.api.nvim_buf_get_name(bufnr))
            if node then
              api.tree.focus(node.id)
            else
              require("neo-tree.sources.filesystem").reveal_current_file(true)
            end
          end)
        end,
      },
    },
  },
  config = function(_, opts)
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("NeoTreeSettings", { clear = true }),
      pattern = "neo-tree",
      callback = function() vim.opt_local.winfixwidth = true end,
    })
    require("neo-tree").setup(opts)
  end,
}
