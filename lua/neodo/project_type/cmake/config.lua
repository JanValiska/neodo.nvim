local M = {}

local Path = require('plenary.path')
local notify = require('neodo.notify')
local log = require('neodo.log')
local cmake_config_file_name = 'neodo_cmake_config.json'
local functions = require('neodo.project_type.cmake.functions')
local Profile = require('neodo.project_type.cmake.profile')

function M.load(project, cmake_project)
    log.debug("CMake load config called")
    if not project:get_data_path() then return end

    if not cmake_project then
        notify.error('Cannot load config, no cmake project type found.', 'NeoDo > CMake')
        return
    end

    local config_file = Path:new(project:get_data_path(), cmake_config_file_name)

    if not config_file:is_file() then
        return
    end

    local data = config_file:read()
    if not data then return end

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
    if selected_profile then functions.switch_compile_commands(selected_profile) end
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

    local config_file = Path:new(project:get_data_path(), cmake_config_file_name)
    config_file:write(vim.fn.json_encode(config), 'w')
    notify.info('Configuration saved', 'NeoDo > CMake')
    if type(callback) == 'function' then callback(true) end
end

return M
