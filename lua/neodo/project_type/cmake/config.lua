local M = {}

local fs = require('neodo.file')
local notify = require('neodo.notify')
local cmake_config_file_name = 'neodo_cmake_config.json'
local functions = require('neodo.project_type.cmake.functions')
local Profile = require('neodo.project_type.cmake.profile')

function M.load(project, cmake_project)
    if not project:get_data_path() then
        return
    end

    if not cmake_project then
        notify.error('Cannot load config, no cmake project type found.', 'NeoDo > CMake')
        return
    end

    local config_file = fs.join_path(project:get_data_path(), cmake_config_file_name)

    fs.read(config_file, 438, function(err, data)
        if not err then
            local config = vim.fn.json_decode(data)
            cmake_project.config = {
                selected_profile = config.selected_profile,
                profiles = {},
            }
            if config.profiles and type(config.profiles) == 'table' then
                for key, profiletable in pairs(config.profiles) do
                    local profile = Profile:new(project, cmake_project)
                    profile:load_from_table(profiletable)
                    cmake_project.config.profiles[key] = profile
                end
            end

            -- switch compile_functions to selected profile
            local selected_profile = functions.get_selected_profile(cmake_project)
            if selected_profile then
                functions.switch_compile_commands(selected_profile)
            end
        end
    end)
end

function M.save(project, cmake_project, callback)
    if not project:get_data_path() then
        notify.error('Cannot save config, project config data path not found', 'NeoDo > CMake')
        return
    end

    if not cmake_project then
        notify.error('Cannot save config, no cmake project type found.', 'NeoDo > CMake')
        return
    end

    local config = {
        selected_profile = cmake_project.config.selected_profile,
        profiles = {},
    }
    if cmake_project.config.profiles then
        for key, profile in pairs(cmake_project.config.profiles) do
            config.profiles[key] = profile:save_to_table()
        end
    end

    local config_file = project:get_data_path() .. '/' .. cmake_config_file_name
    fs.write(config_file, 444, vim.fn.json_encode(config), function()
        -- TODO: check if config successully written
        notify.info('Configuration saved', 'NeoDo > CMake')
        if type(callback) == "function" then
            callback(true)
        end
    end)
end

return M
