local M = {}

local global_settings = require 'neodo.settings'

-- TODO: use something portable to make parent directory
local function get_parent_path(path)
    local pattern = "^(.+)/"
    return string.match(path, pattern)
end

local function directory_find_backwards(path, file)
    while true do
        local data = vim.loop.fs_scandir(path)
        if not data then return nil end
        local function iter() return vim.loop.fs_scandir_next(data) end
        for name, _ in iter do if name == file then return path end end
        path = get_parent_path(path)
        if path == nil then break end
    end
    return nil
end

function M.find_project_root_and_type(path, callback)
    vim.schedule(function()
        for type, value in pairs(global_settings.project_type) do
            for _, pattern in ipairs(value.patterns) do
                local dir = directory_find_backwards(path, pattern)
                if dir then callback({dir = dir, type = type}) end
            end
        end
    end)
end

return M
