local M = {}

local Path = require('plenary.path')
local log = require('neodo.log')

local global_settings = require('neodo.settings')

local function find_project_types(root, registered_project_types)
    local project_types = {}
    while true do
        log('Scanning:', root)
        local data = vim.loop.fs_scandir(root)
        if not data then break end

        -- check files in current directory
        local function iter() return vim.loop.fs_scandir_next(data) end

        for name, _ in iter do
            for key, registered_type in pairs(registered_project_types) do
                for _, pattern in ipairs(registered_type.patterns) do
                    if name == pattern then
                        project_types[key] = root
                        goto continue
                    end
                end
                ::continue::
            end
        end

        if root == Path.path.root(root) then break end
        root = Path:new(root):parent():absolute()
    end
    return project_types
end

function M.find_project_types(basepath, callback)
    local folder_and_types = find_project_types(basepath, global_settings.project_types)
    if type(callback) == 'function' then callback(folder_and_types) end
end

return M
