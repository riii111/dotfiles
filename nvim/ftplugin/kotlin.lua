-- Kotlinだけ起動漏れがあったため、暫定でftplugin側で直接 lsp.startする
-- 将来は plugins/languages/kotlin.lua へ戻して統一予定

-- Prefer Temurin JDK 21 for kotlin-lsp
local jdk21 = vim.fn.systemlist("/usr/libexec/java_home -v 21")[1]
if jdk21 and #jdk21 > 0 then
  vim.env.JAVA_HOME = jdk21
  vim.env.PATH = jdk21 .. "/bin:" .. vim.env.PATH
end

local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/kotlin-lsp"
local cmd = vim.fn.executable(mason_bin) == 1 and { mason_bin, "--stdio" } or { "kotlin-lsp", "--stdio" }

-- simple root detection
local root = vim.fs.root(0, { "settings.gradle.kts", "settings.gradle", "build.gradle.kts", "build.gradle", ".git" })
if not root then
  return
end

-- avoid duplicate attach
for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
  if client.name == "kotlin_lsp" then
    return
  end
end

local capabilities = vim.lsp.protocol.make_client_capabilities()

vim.lsp.start({
  name = "kotlin_lsp",
  cmd = cmd,
  cmd_env = {
    JAVA_HOME = vim.env.JAVA_HOME,
    JDK_HOME = vim.env.JAVA_HOME,
    PATH = vim.env.PATH,
  },
  root_dir = root,
  filetypes = { "kotlin" },
  capabilities = capabilities,
  on_attach = function(client, bufnr)
    vim.diagnostic.config({
      virtual_text = true,
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
    })
    local ok, actions = pcall(require, "utils.lsp-actions")
    if ok then
      local opts = { buffer = bufnr, silent = true }
      vim.keymap.set("n", "<M-CR>", actions.language_specific_code_action, opts)
      vim.keymap.set("n", "<D-S-r>", actions.kotlin_refactor_menu, opts)
      vim.keymap.set("n", "<M-S-r>", actions.kotlin_refactor_menu, opts)
    end
  end,
})
