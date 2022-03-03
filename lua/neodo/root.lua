local M = {}

local global_settings = require("neodo.settings")

-- TODO: use something portable to make parent directory
local function get_parent_path(path)
	local pattern = "^(.+)/"
	return string.match(path, pattern)
end

local function directory_find_backwards(path, pattern)
	local p = ""
	while true do
		local data = vim.loop.fs_scandir(path)
		if not data then
			break
		end

		-- check files in current directory
		local function iter()
			return vim.loop.fs_scandir_next(data)
		end
		for name, _ in iter do
			if name == pattern then
				p = path
			end
		end

		-- scan parent dir
		path = get_parent_path(path)
		if path == nil then
			break
		end
	end
	return p
end

function M.find_project(file_basepath, callback)
	vim.schedule(function()
		-- look for project types
		for type, value in pairs(global_settings.project_type) do
			for _, pattern in ipairs(value.patterns) do
				local path = directory_find_backwards(file_basepath, pattern)
				if path and path ~= "" then
					callback({ path = path, type = type })
					return
				end
			end
		end

		-- look for generic project root
		for _, pattern in ipairs(global_settings.root_patterns) do
			local path = directory_find_backwards(file_basepath, pattern)
			if path and path ~= "" then
				callback({ path = path, type = nil })
				return
			end
		end

		-- no project root or type found
		callback({ path = nil, type = nil })
	end)
end

return M
