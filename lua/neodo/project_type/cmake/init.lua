local M = {}

local picker = require 'neodo.picker'
local notify = require 'neodo.notify'
local fs = require 'neodo.file'

local cmake_config_file_name = 'neodo_cmake_config.json'

local targets = {}

local function load_config(project)
    if not project.data_path then return end
    local config_file = project.data_path .. "/" .. cmake_config_file_name
    fs.file_exists('compile_commands.json')
    fs.read(config_file, 438, function(err, data)
        if err then
            return
        else
            local config = vim.fn.json_decode(data)
            project.config = config
            project.config.has_conan = fs.file_exists('conanfile.txt')
        end
    end)
end

local function save_config(project)
    local config_file = project.data_path .. "/" .. cmake_config_file_name
    fs.write(config_file, 444, vim.fn.json_encode(project.config),
             function() notify.info("Configuration saved", "NeoDo > CMake") end)
end

local function select_profile(profile_key, project)
    project.config.selected_profile = profile_key
    local profile = project.config.profiles[profile_key]
    if profile.configured then
        if fs.file_exists('compile_commands.json') then
            fs.delete('compile_commands.json')
        end
        fs.symlink(profile.build_dir .. '/compile_commands.json', 'compile_commands.json')
    end
end

local function create_profile(_, project)
    local profile = {}
    profile.name = vim.fn.input("Profile name: ")
    if not profile.name then return end
    local profile_key = string.gsub(profile.name, "%s+", "-")
    profile.build_dir = 'build-' .. profile_key
    fs.mkdir(profile.build_dir)
    profile.cmake_params = vim.fn.input("CMake params: ",
                                        "-DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=1")
    profile.configured = false
    project.config.profiles[profile_key] = profile
    select_profile(profile_key, project)
    save_config(project)
    return {type = 'success'}
end

local function configure(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    local cmd = ''
    print(vim.inspect(project.config))
    if project.config.has_conan then
        cmd = 'conan install -if ' .. profile.build_dir .. ' . && '
    end
    cmd = cmd .. "cmake -B " .. profile.build_dir .. ' ' .. profile.cmake_params
    return {type = 'success', text = cmd}
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
                name = "CMake > Create profile",
                notify = false,
                cmd = create_profile
            },
            select_profile = {
                type = 'function',
                name = "CMake > Select profile",
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
                name = "CMake > Delete profile",
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
                name = "CMake > Select target",
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
            conan_install = {
                type = 'terminal',
                name = 'CMake > Install conan packages',
                cmd = function(_, project)
                    local profile = project.config.profiles[project.config
                                        .selected_profile]
                    local cmd = 'conan install -if ' .. profile.build_dir .. ' .'
                    return {type = 'success', text = cmd}
                end,
                enabled = function(_, project)
                    return project.config.has_conan and
                               project.config.selected_profile
                end
            },
            configure = {
                type = 'terminal',
                name = "CMake > Configure",
                cmd = configure,
                enabled = function(_, project)
                    return project.config.selected_profile ~= nil
                end,
                on_success = function(project)
                    project.config.profiles[project.config.selected_profile]
                        .configured = true
                    save_config(project)
                end
            }
        },
        statusline = function(project)
            local statusline = ' CMake'
            if project.config.selected_profile then
                statusline = statusline .. "  " ..
                                 project.config.selected_profile
                local profile = project.config.profiles[project.config
                                    .selected_profile]
                if profile.configured == false then
                    statusline = statusline .. '(unconfigured)'
                end
            end
            if project.config.selected_target then
                statusline = statusline .. " ⦿ " ..
                                 project.config.selected_target
            end
            return statusline
        end
    }
end

return M
