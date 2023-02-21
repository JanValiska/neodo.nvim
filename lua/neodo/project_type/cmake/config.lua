local M = {}

local fs = require("neodo.file")
local code_model = require("neodo.project_type.cmake.code_model")
local notify = require("neodo.notify")
local cmake_config_file_name = "neodo_cmake_config.json"
local functions = require('neodo.project_type.cmake.functions')

function M.load(project, cmake_project)
    if not project.data_path() then
        return
    end

    if not cmake_project then
        notify.error("Cannot load config, no cmake project type found.", "NeoDo > CMake")
        return
    end

    local config_file = fs.join_path(project.data_path(), cmake_config_file_name)

    fs.read(config_file, 438, function(err, data)
        if not err then
            local config = vim.fn.json_decode(data)
            cmake_project.config = config
            for key, profile in pairs(cmake_project.config.profiles) do
                if profile.configured then
                    cmake_project.code_models[key] = code_model:new(profile.build_dir)
                end
            end
            for _, cm in pairs(cmake_project.code_models) do
                cm:read_reply()
            end

            -- switch compile_functions to selected profile
            local selected_profile = functions.get_selected_profile(cmake_project)
            if selected_profile then
                functions.switch_compile_commands(selected_profile)
            end
        end
    end)
end

function M.save(project, cmake_project)
    if not project.data_path() then
        notify.error("Cannot save config, project config data path not found", "NeoDo > CMake")
        return
    end

    if not cmake_project then
        notify.error("Cannot save config, no cmake project type found.", "NeoDo > CMake")
        return
    end

    local config_file = project.data_path() .. "/" .. cmake_config_file_name
    fs.write(config_file, 444, vim.fn.json_encode(cmake_project.config), function()
        notify.info("Configuration saved", "NeoDo > CMake")
    end)
end

return M
