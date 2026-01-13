-- Lazy require utilities for deferred module loading
-- Use this to create keymaps that don't require modules until invoked

local M = {}

--- Create a function that lazily requires a module and calls a function on it
--- @param module string The module path to require
--- @param func string The function name to call on the module
--- @return function A function that requires the module and calls func with any passed arguments
function M.call(module, func)
	return function(...)
		return require(module)[func](...)
	end
end

--- Create a function that lazily requires a module and returns it
--- @param module string The module path to require
--- @return function A function that requires and returns the module
function M.require(module)
	return function()
		return require(module)
	end
end

--- Create a function that lazily requires a module and accesses a nested path
--- @param module string The module path to require
--- @param path string Dot-separated path to nested value (e.g., "builtin.find_files")
--- @return function A function that requires the module and returns the nested value
function M.get(module, path)
	return function(...)
		local mod = require(module)
		for key in path:gmatch("[^.]+") do
			mod = mod[key]
		end
		if type(mod) == "function" then
			return mod(...)
		end
		return mod
	end
end

return M
