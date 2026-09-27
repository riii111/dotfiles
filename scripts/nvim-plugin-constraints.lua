local git = require("lazy.manage.git")
local semver = require("lazy.manage.semver")
local config = require("lazy.core.config")
local report = vim.empty_dict()

for name, plugin in pairs(config.plugins) do
	local constraint = plugin.version
	if constraint == nil and plugin.branch == nil then
		constraint = config.options.defaults.version
	end
	if type(constraint) == "string" then
		local versions = {}
		for _, tag in ipairs(git.get_tags(plugin.dir)) do
			local version = semver.version(tag)
			if version and not version.prerelease then
				version.tag = tag
				table.insert(versions, version)
			end
		end
		local newest = semver.last(versions)
		local selected = semver.last(git.get_versions(plugin.dir, constraint))
		if newest and (not selected or newest > selected) and not semver.range(constraint):matches(newest) then
			local result = vim.system({ "git", "-C", plugin.dir, "rev-list", "-n", "1", newest.tag }, { text = true })
				:wait()
			if result.code == 0 then
				report[name] = { outside_version = newest.tag, outside_commit = vim.trim(result.stdout) }
			end
		end
	end
end

return report
