return {
  "mrcjkb/rustaceanvim",
  version = "^4",
  ft = { "rust" },
  enabled = function()
    local cwd = vim.fn.getcwd()
    local disable_path_pattern = "/Users/a81803/GitHub/0_private/products/miniOS"

    if string.find(cwd, disable_path_pattern, 1, true) then
      vim.notify(
        "Current project (" .. cwd .. ") matches disable pattern: Disabling rustaceanvim plugin.",
        vim.log.levels.INFO
      )
      return false
    else
      return true
    end
  end,
  opts = {
    server = {
      settings = {
        ["rust-analyzer"] = {
          cargo = {
            -- loadOutDirsFromCheck = true,
          },
        },
      },
    },
  },
}
