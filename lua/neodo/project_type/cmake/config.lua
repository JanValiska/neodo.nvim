local M = {}

local fs = require("neodo.file")
local code_model = require("neodo.project_type.cmake.code_model")
local notify = require("neodo.notify")
local cmake_config_file_name = "neodo_cmake_config.json"

function M.load(project)
    if not project.data_path then
        return
    end
    local config_file = project.data_path .. "/" .. cmake_config_file_name
    fs.file_exists("compile_commands.json")
    local function load_conan()
        project.config.has_conan = fs.file_exists("conanfile.txt")
    end

    fs.read(config_file, 438, function(err, data)
        if err then
            load_conan()
            return
        else
            local config = vim.fn.json_decode(data)
            project.config = config
            for key, profile in pairs(project.config.profiles) do
                if profile.configured then
                    project.code_models[key] = code_model:new(profile.build_dir)
                end
            end
            for _, cm in pairs(project.code_models) do
                cm:read_reply()
            end
            load_conan()
        end
    end)
end

function M.save(project)
    if not project.data_path then
        notify.error("Cannot save config, project config data path not found", "NeoDo > CMake")
        return
    end
    local config_file = project.data_path .. "/" .. cmake_config_file_name
    fs.write(config_file, 444, vim.fn.json_encode(project.config), function()
        notify.info("Configuration saved", "NeoDo > CMake")
    end)
end

return M
