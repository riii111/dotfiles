-- 参考: https://docs.astronvim.com/recipes/mappings/
return {
  {
    "AstroNvim/astrocore",
    ---@type AstroCoreOpts
    opts = {
      mappings = {
        n = {
          -- User Mappings
          ["<D-Down>"] = { ":split<CR>", desc = "Split window below (下に画面分割)" },
          ["<D-Right>"] = { ":vsplit<CR>", desc = "Split window right (右に画面分割)" }, -- cmd+right (Ghostty unbind前提)
          ["<C-d>"] = { "x", desc = "Forward delete character" }, -- Override default scroll

          -- Search (検索) - Telescope を使用
          ["<C-h>"] = {
            function()
              require("telescope.builtin").live_grep()
            end,
            desc = "Search text in project (プロジェクト内テキスト検索)",
          }, -- ctrl+h で Telescope の live_grep を起動
          ["<D-S-f>"] = { function() require("telescope").extensions.live_grep_args.live_grep_args() end, desc = "Live Grep with Args" }, -- Use live_grep_args extension
          ["<D-f>"] = { function() require("telescope.builtin").current_buffer_fuzzy_find() end, desc = "Find in current buffer (ファイル内検索)" }, -- Cmd+F
          ["<D-p>"] = { function() require("telescope.builtin").find_files() end, desc = "Find files (ファイル検索)"}, -- cmd+p (Ghostty unbind前提)

          -- Commenting (コメントアウト) - Comment.nvim を使用
          ["<D-/>"] = { function() require("Comment.api").toggle.linewise.current() end, desc = "Toggle comment (コメント切り替え)" }, -- cmd+/ (Ghostty unbind前提)

          -- Terminal (ターミナル) - toggleterm.nvim を使用 (Astronvim標準)
          ["<C-S-@>"] = { ":ToggleTerm<CR>", desc = "Toggle terminal (ターミナル切り替え)" }, -- ctrl+shift+@

          -- which-key のメニュー表示用 (desc のみ) - Cmdキーに置き換えたものは不要になる
          ["<Leader>xx"] = { ":echo 'Leader xx pressed!'<CR>", desc = "Test Leader mapping" }, -- テスト用は残しておく

          -- Buffer Operations (バッファ操作)
          ["<D-M-Right>"] = { ":bnext<CR>", desc = "Next buffer (次のバッファ)" },
          ["<D-M-Left>"] = { ":bprevious<CR>", desc = "Previous buffer (前のバッファ)" },
          ["<Leader>t"] = { ":enew<CR>", desc = "New buffer (新規バッファ)" },     -- <M-t> から変更
          ["<Leader>w"] = { ":bdelete<CR>", desc = "Close buffer (バッファを閉じる)" }, -- <M-w> から変更

          -- LSP Navigation (LSP ナビゲーション) F12認識しない
          -- ["F12"] = { function() require("telescope.builtin").lsp_definitions() end, desc = "Go to Definition (Telescope)" }, -- Changed from vim.lsp.buf.definition()
          -- ["<S-F12>"] = { function() require("telescope.builtin").lsp_references() end, desc = "Find References (参照を検索)" }, -- Reverted to S-F12

          -- Markdown Preview (markview.nvim)
          ["<D-S-v>"] = { function() vim.cmd("MarkviewOpen") end, desc = "Markdown Preview (Markview)" }, -- Cmd+Shift+V

          -- Indentation Mappings (インデント操作)
          ["<Tab>"] = { ">>", desc = "Indent line (行インデント)" },
          ["<S-Tab>"] = { "<<", desc = "Unindent line (行インデント解除)" },
        },
        v = {
          -- User Mappings
          ["<D-/>"] = { "<ESC><CMD>require('Comment.api').toggle.linewise(vim.fn.visualmode())<CR>", desc = "Toggle comment (コメント切り替え)" }, -- cmd+/ (Ghostty unbind前提)
          ["<D-c>"] = { '"+y', desc = "Copy to system clipboard" }, -- Requires Ghostty unbind: super+c

          -- Indentation Mappings (インデント操作)
          ["<Tab>"] = { ">gv", desc = "Indent selection (選択範囲インデント)" },
          ["<S-Tab>"] = { "<gv", desc = "Unindent selection (選択範囲インデント解除)" },
        },
        i = {
          -- Buffer Operations (バッファ操作)
          ["<C-Tab>"] = { "<Esc>:bnext<CR>a", desc = "Next buffer (次のバッファ)" },
          ["<C-S-Tab>"] = { "<Esc>:bprevious<CR>a", desc = "Previous buffer (前のバッファ)" },
          ["<C-d>"] = { "<Del>", desc = "Forward delete character" },

          -- Indentation Mappings (インデント操作)
          ["<S-Tab>"] = { "<C-d>", desc = "Unindent line (行インデント解除)" },
        },
        t = {
          -- User Mappings (from lua/user/mappings.lua)
          -- (現状なし)
        },
      },
    },
  },
} 
