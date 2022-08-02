local M = {}

local compilers = require("neodo.compilers")
local config = require("neodo.project_type.cmake.config")
local commands = require("neodo.project_type.cmake.commands")

M.register = function()
    local settings = require("neodo.settings")
    settings.project_type.cmake = {
        name = "CMake",
        patterns = { "CMakeLists.txt" },
        on_attach = function(project)
            config.load(project)
        end,
        user_on_attach = nil,
        buffer_on_attach = nil,
        user_buffer_on_attach = nil,
        config = { selected_target = nil, selected_profile = nil, profiles = {}, build_configurations = nil },
        code_models = {},
        commands = {
            create_profile = {
                type = "function",
                name = "CMake > Create profile",
                notify = false,
                cmd = commands.create_profile,
            },
            select_profile = {
                type = "function",
                name = "CMake > Select profile",
                notify = false,
                cmd = commands.select_profile,
                enabled = commands.select_profile_enabled,
            },
            delete_profile = {
                type = "function",
                name = "CMake > Delete profile",
                notify = false,
                cmd = commands.delete_profile,
                enabled = commands.delete_profile_enabled,
            },
            select_target = {
                type = "function",
                name = "CMake > Select target",
                notify = false,
                cmd = commands.select_target,
                enabled = commands.select_target_enabled,
            },
            clean = {
                type = "background",
                name = "Clean",
                cmd = commands.clean,
                enabled = commands.clean_enabled,
            },
            build_all = {
                type = "terminal",
                name = "CMake > Build all",
                cmd = commands.build_all,
                enabled = commands.build_all_enabled,
                errorformat = compilers.get_errorformat("gcc"),
            },
            build_selected_target = {
                type = "terminal",
                name = "CMake > Build selected target",
                cmd = commands.build_selected_target,
                enabled = commands.build_selected_target_enabled,
                errorformat = compilers.get_errorformat("gcc"),
            },
            run_selected_target = {
                type = "terminal",
                name = "CMake > Run selected target",
                cmd = commands.run_selected_target,
                enabled = commands.run_selected_target_enabled,
            },
            conan_install = {
                type = "terminal",
                name = "CMake > Install conan packages",
                cmd = commands.conan_install,
                enabled = commands.conan_install_enabled,
            },
            configure = {
                type = "terminal",
                name = "CMake > Configure",
                cmd = commands.configure,
                enabled = commands.configure_enabled,
                on_success = commands.configure_on_success,
            },
        },
        statusline = require('neodo.project_type.cmake.statusline').statusline,
    }
end

return M
