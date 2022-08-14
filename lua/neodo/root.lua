local M = {}

local global_settings = require("neodo.settings")

-- TODO: use something portable to make parent directory
local function get_parent_path(path)
    local pattern = "^(.+)/"
    return string.match(path, pattern)
end

local function find_project_folder_and_types(basepath, project_types)
    local path = nil
    local path_len = 0
    local project_types_keys = nil
    local basepath_len = string.len(basepath)
    while true do
        local data = vim.loop.fs_scandir(basepath)
        if not data then
            break
        end

        -- check files in current directory
        local function iter()
            return vim.loop.fs_scandir_next(data)
        end

        for name, _ in iter do
            for key, project_type in pairs(project_types) do
                for _, pattern in ipairs(project_type.patterns) do
                    if name == pattern then
                        if path == nil then
                            path = basepath
                            path_len = string.len(path)
                        else if path ~= nil and path_len > basepath_len then
                                path = basepath
                                project_types_keys = nil
                            end
                        end
                        if project_types_keys == nil then
                            project_types_keys = { key }
                        else
                            table.insert(project_types_keys, key)
                        end
                        goto continue
                    end
                end
                ::continue::
            end
        end

        -- scan parent dir
        basepath = get_parent_path(basepath)
        if basepath == nil then
            break
        end
        basepath_len = string.len(basepath)
    end
    return { path = path, project_types_keys = project_types_keys }
end

function M.find_project(basepath, callback)
    vim.schedule(function()
        local folder_and_types = find_project_folder_and_types(basepath, global_settings.project_types)
        callback(folder_and_types)
    end)
end

return M
