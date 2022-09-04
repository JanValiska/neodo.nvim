local M = {}

local notify = require("neodo.notify")
local compilers = require("neodo.compilers")
local config = require("neodo.project_type.cmake.config")
local commands = require("neodo.project_type.cmake.commands")

M.register = function()
    local settings = require("neodo.settings")
    settings.project_types.cmake = {
        name = "CMake",
        patterns = { "CMakeLists.txt" },
        on_attach = function(ctx)
            local function load_config()
                config.load(ctx.project, ctx.project_type)
            end

            if not ctx.project.config_file() then
                ctx.project.create_config_file(function(result)
                    if result then
                        load_config()
                    else
                        notify.error("CMake project_type needs project data_path, but cannot be created.")
                    end
                end)
            else
                load_config()
            end
        end,
        user_on_attach = nil,
        buffer_on_attach = nil,
        user_buffer_on_attach = nil,
        config = { selected_target = nil, selected_profile = nil, profiles = {}, build_configurations = nil },
        code_models = {},
        commands = {
            create_profile = {
                name = "Create profile",
                notify = false,
                fn = commands.create_profile,
            },
            select_profile = {
                name = "Select profile",
                notify = false,
                fn = commands.select_profile,
                enabled = commands.select_profile_enabled,
            },
            delete_profile = {
                name = "Delete profile",
                notify = false,
                fn = commands.delete_profile,
                enabled = commands.delete_profile_enabled,
            },
            select_target = {
                name = "Select target",
                notify = false,
                fn = commands.select_target,
                enabled = commands.select_target_enabled,
            },
            clean = {
                name = "Clean",
                background = true,
                cmd = commands.clean,
                enabled = commands.clean_enabled,
            },
            build_all = {
                name = "Build all",
                cmd = commands.build_all,
                enabled = commands.build_all_enabled,
                errorformat = compilers.get_errorformat("gcc"),
            },
            build_selected_target = {
                name = "Build selected target",
                cmd = commands.build_selected_target,
                enabled = commands.build_selected_target_enabled,
                errorformat = compilers.get_errorformat("gcc"),
            },
            run_selected_target = {
                name = "Run selected target",
                cmd = commands.run_selected_target,
                enabled = commands.run_selected_target_enabled,
            },
            conan_install = {
                name = "Install conan packages",
                cmd = commands.conan_install,
                enabled = commands.conan_install_enabled,
            },
            show_cache_variables = {
                name = "Show cache variables",
                cmd = commands.show_cache_variables,
                enabled = commands.show_cache_variables_enabled,
                keep_terminal_open = true
            },
            configure = {
                name = "Configure",
                cmd = commands.configure,
                enabled = commands.configure_enabled,
                on_success = commands.configure_on_success,
            },
        },
        statusline = require('neodo.project_type.cmake.statusline').statusline,
    }
end

return M
