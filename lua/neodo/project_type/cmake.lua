local M = {}

local picker = require 'neodo.picker'
local notify = require 'neodo.notify'
local file = require 'neodo.file'

local cmake_config_file_name = 'neodo_cmake_config.json'

local targets = {}

local function load_config(project)
    local config_file = project.data_path .. "/" .. cmake_config_file_name
    file.read(config_file, 438, function(err, data)
        if err then
            return
        else
            local config = vim.fn.json_decode(data)
            project.config = config
        end
    end)
end

local function save_config(project)
    local config_file = project.data_path .. "/" .. cmake_config_file_name
    file.write(config_file, 444, vim.fn.json_encode(project.config), function()
        notify.info("Configuration saved", "NeoDo > CMake")
    end)
end

local function select_profile(profile_key, project)
    project.config.selected_profile = profile_key
    -- TODO: ln -s compile_commands.json
end

local function create_profile(_, project)
    local profile = {}
    profile.name = vim.fn.input("Profile name: ")
    if not profile.name then return end
    local profile_key = string.gsub(profile.name, "%s+", "-")
    profile.build_dir = 'build-' .. profile_key
    profile.cmake_params = vim.fn.input("CMake params: ",
                                        "-DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=1")
    profile.configured = false
    project.config.profiles[profile_key] = profile
    select_profile(profile_key, project)
    save_config(project)
    return {type = 'success'}
end

M.register = function()
    local settings = require 'neodo.settings'
    settings.project_type.cmake = {
        patterns = {'CMakeLists.txt'},
        on_attach = function(project) load_config(project) end,
        user_on_attach = nil,
        buffer_on_attach = nil,
        user_buffer_on_attach = nil,
        config = {selected_target = nil, selected_profile = nil, profiles = {}},
        commands = {
            create_profile = {
                type = 'function',
                name = "Create profile",
                notify = false,
                cmd = create_profile
            },
            select_profile = {
                type = 'function',
                name = "Select profile",
                notify = false,
                cmd = function(_, project)
                    picker.pick("Select profile",
                                vim.tbl_keys(project.config.profiles),
                                function(profile)
                        select_profile(profile, project)
                    end, {})
                    return {type = 'success'}
                end,
                enabled = function(_, project)
                    return vim.tbl_count(project.config.profiles) ~= 0
                end
            },
            delete_profile = {
                type = 'function',
                name = "Delete profile",
                notify = false,
                cmd = function(_, project)
                    picker.pick("Select profile to delete",
                                vim.tbl_keys(project.config.profiles),
                                function(selection)
                        notify.info("Selected: " .. selection,
                                    "NeoDo: CMake > Delete profile")
                    end, {})
                    return {type = 'success'}
                end,
                enabled = function(_, project)
                    return vim.tbl_count(project.config.profiles) ~= 0
                end
            },
            select_target = {
                type = 'function',
                name = "Select target",
                notify = false,
                cmd = function(_, _)
                    picker.pick("Select target", vim.tbl_keys(targets),
                                function(selection)
                        notify.info("Selected: " .. selection,
                                    "NeoDo: CMake > Select target")
                    end, {})
                    return {type = 'success'}
                end,
                enabled = function(_, _)
                    return vim.tbl_count(targets) ~= 0
                end
            },
            build_all = {
                type = 'terminal',
                name = "CMake > Build all",
                cmd = function(_, project)
                    local profile = project.config.profiles[project.config
                                        .selected_profile]
                    local cmd = "cmake --build " .. profile.build_dir
                    return {type = 'success', text = cmd}
                end,
                enabled = function(_, project)
                    return project.config.selected_profile ~= nil and
                               project.config.profiles[project.config
                                   .selected_profile].configured == true
                end,
                errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
            },
            build_selected_target = {
                type = 'terminal',
                name = "CMake > Build selected target",
                cmd = function(_, project)
                    if project.config.selected_target == nil then
                        return {type = 'error', text = "No target selected"}
                    end

                    return {
                        type = 'success',
                        text = 'cmake --build build-debug --target ' ..
                            project.config.selected_target
                    }

                end,
                enabled = function(_, project)
                    return project.config.selected_target ~= nil
                end,
                errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
            },
            run_selected_target = {
                type = 'terminal',
                name = 'CMake > Run selected target',
                cmd = function(_, _)
                    return {type = 'error', text = 'Not implemented'}
                end
            },
            configure = {
                type = 'terminal',
                name = "CMake > Configure",
                cmd = function(_, project)
                    local profile = project.config.profiles[project.config
                                        .selected_profile]
                    local cmd = "cmake -B " .. profile.build_dir .. ' ' ..
                                    profile.cmake_params
                    return {type = 'success', text = cmd}
                end,
                on_success = function(project)
                    project.config.profiles[project.config.selected_profile]
                        .configured = true
                    save_config(project)
                end
            }
        }
    }
end

return M
