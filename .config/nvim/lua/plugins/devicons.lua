local function apply_custom_devicons()
	if vim.g.colors_name ~= "custom-theme-riii111" then
		return
	end

	local devicons = require("nvim-web-devicons")
	local palette = require("custom-theme-riii111").palette()
	local colors = palette.devicons

	devicons.set_icon({
		lua = { icon = "󰢱", color = colors.blue, name = "Lua" },
		go = { icon = "󰟓", color = palette.languages.go, name = "Go" },
		kotlin = { icon = "󱈙", color = palette.languages.kotlin, name = "Kotlin" },
		kt = { icon = "󱈙", color = palette.languages.kotlin, name = "Kotlin" },
		kts = { icon = "󱈙", color = palette.languages.kotlin, name = "KotlinScript" },
		toml = { icon = "󰿘", color = colors.pink, name = "Toml" },
		dockerfile = { icon = "󰡨", color = colors.blue, name = "Dockerfile" },
		rust = { icon = "󱘗", color = palette.languages.rust, name = "Rust" },
		rs = { icon = "󱘗", color = palette.languages.rust, name = "Rust" },
		js = { icon = "󰌞", color = palette.languages.javascript, name = "JavaScript" },
		ts = { icon = "󰛦", color = palette.languages.typescript, name = "TypeScript" },
		json = { icon = "󰘦", color = palette.languages.javascript, name = "JSON" },
		yaml = { icon = "󰈙", color = colors.mauve, name = "YAML" },
		yml = { icon = "󰈙", color = colors.mauve, name = "YAML" },
		md = { icon = "󰍔", color = colors.text, name = "Markdown" },
		sql = { icon = "󰆼", color = colors.pink, name = "SQL" },
		py = { icon = "󰌠", color = colors.blue, name = "Python" },
	})

	devicons.set_default_icon("󰈔", colors.text)

	devicons.setup({
		override_by_filename = {
			[".gitignore"] = { icon = "", color = colors.overlay0, name = "GitIgnore" },
			["README.md"] = { icon = "󰍔", color = colors.text, name = "Readme" },
			["Cargo.toml"] = { icon = "", color = palette.languages.rust, name = "Cargo" },
			["Cargo.lock"] = { icon = "", color = colors.overlay0, name = "CargoLock" },
			["go.mod"] = { icon = "󰟓", color = colors.text, name = "GoMod" },
			["go.sum"] = { icon = "󰟓", color = colors.text, name = "GoSum" },
			["build.gradle"] = { icon = "󱈙", color = palette.languages.kotlin, name = "Gradle" },
			["build.gradle.kts"] = { icon = "󱈙", color = palette.languages.kotlin, name = "GradleKotlin" },
			["settings.gradle"] = { icon = "󱈙", color = colors.text, name = "GradleSettings" },
			["settings.gradle.kts"] = { icon = "󱈙", color = colors.text, name = "GradleSettingsKotlin" },
			["package.json"] = { icon = "", color = palette.languages.javascript, name = "PackageJson" },
			["package-lock.json"] = { icon = "", color = colors.overlay0, name = "PackageLock" },
			["tsconfig.json"] = { icon = "", color = palette.languages.typescript, name = "TSConfig" },
		},
		override_by_extension = {
			["log"] = { icon = "󰌱", color = colors.overlay0, name = "Log" },
		},
		default = true,
		color_icons = true,
	})
end

return {
	{
		"nvim-tree/nvim-web-devicons",
		lazy = false,
		config = function()
			local devicons = require("nvim-web-devicons")

			devicons.setup({
				default = true,
				color_icons = true,
			})

			apply_custom_devicons()

			vim.api.nvim_create_autocmd("ColorScheme", {
				pattern = "custom-theme-riii111",
				callback = apply_custom_devicons,
				group = vim.api.nvim_create_augroup("DeviconsCustomTheme", { clear = true }),
			})
		end,
	},
}
