local M = {}

local global_settings = require 'neodo.settings'

-- TODO: use something portable to make parent directory
local function get_parent_path(path)
    local pattern = "^(.+)/"
    return string.match(path, pattern)
end

local function directory_find_backwards(path, pattern)
    local p = ''
    while true do
        local data = vim.loop.fs_scandir(path)
        if not data then break end

        -- check files in current directory
        local function iter() return vim.loop.fs_scandir_next(data) end
        for name, _ in iter do
            if name == pattern then
                print("found pattern: " .. name .. " in ")
                p = path
            end
        end

        -- scan parent dir
        path = get_parent_path(path)
        if path == nil then break end
    end
    return p
end

function M.find_project_root_and_type(path, callback)
    vim.schedule(function()
        for type, value in pairs(global_settings.project_type) do
            for _, pattern in ipairs(value.patterns) do
                local dir = directory_find_backwards(path, pattern)
                if dir and dir ~= '' then
                    callback({dir = dir, type = type})
                    return
                end
            end
        end
    end)
end

return M
