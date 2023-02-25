local M = {}

local notify = require('neodo.notify')
local compilers = require('neodo.compilers')
local config = require('neodo.project_type.cmake.config')
local commands = require('neodo.project_type.cmake.commands')
local fs = require('neodo.file')

M.register = function()
    local settings = require('neodo.settings')
    settings.project_types.cmake = {
        name = 'CMake',
        patterns = { 'CMakeLists.txt' },
        on_attach = {
            function(ctx)
                local function load_config()
                    config.load(ctx.project, ctx.project_type)
                end
                ctx.project_type.has_conan = fs.file_exists('conanfile.txt')

                if not ctx.project:get_config_file() then
                    ctx.project.create_config_file(function(result)
                        if result then
                            load_config()
                        else
                            notify.error('CMake project_type needs project data_path, but cannot be created.')
                        end
                    end)
                else
                    load_config()
                end
            end,
        },
        get_info_node = commands.get_info_node,
        autoconfigure = true,
        conan_auto_install = true,
        has_conan = false,
        buffer_on_attach = {},
        config = { selected_target = nil, selected_profile = nil, profiles = {} },
        code_models = {},
        build_configurations = {
            default = {
                name = 'Default',
            },
        },
        commands = {
            create_profile = {
                name = 'Create profile',
                notify = false,
                fn = commands.create_profile,
            },
            select_profile = {
                name = 'Select profile',
                notify = false,
                fn = commands.select_profile,
                enabled = commands.select_profile_enabled,
            },
            delete_profile = {
                name = 'Delete profile',
                notify = false,
                fn = commands.delete_profile,
                enabled = commands.delete_profile_enabled,
            },
            select_target = {
                name = 'Select target',
                notify = false,
                fn = commands.select_target,
                enabled = commands.select_target_enabled,
            },
            clean = {
                name = 'Clean',
                background = true,
                cmd = commands.clean,
                enabled = commands.clean_enabled,
            },
            build_all = {
                name = 'Build all',
                cmd = commands.build_all,
                enabled = commands.build_all_enabled,
                errorformat = compilers.get_errorformat('gcc'),
            },
            build_selected_target = {
                name = 'Build selected target',
                cmd = commands.build_selected_target,
                enabled = commands.build_selected_target_enabled,
                errorformat = compilers.get_errorformat('gcc'),
            },
            run_selected_target = commands.run_selected_target({
                name = 'Run selected target',
            }),
            debug_selected_target = commands.debug_selected_target({
                name = 'Debug selected target',
            }),
            conan_install = {
                name = 'Install conan packages',
                cmd = commands.conan_install,
                enabled = commands.conan_install_enabled,
                on_success = commands.conan_install_on_success,
            },
            select_conan_profile = {
                name = 'Select conan profile',
                notify = false,
                fn = commands.select_conan_profile,
                enabled = commands.select_conan_profile_enabled,
            },
            show_cache_variables = {
                name = 'Show cache variables',
                cmd = commands.show_cache_variables,
                enabled = commands.show_cache_variables_enabled,
                keep_terminal_open = true,
            },
            configure = {
                name = 'Configure',
                cmd = commands.configure,
                enabled = commands.configure_enabled,
                on_success = commands.configure_on_success,
            },
            change_build_configuration = {
                name = 'Change build configuration',
                fn = commands.change_build_configuration,
                enabled = commands.has_selected_profile,
            },
            rename_profile = {
                name = 'Rename profile',
                fn = commands.rename_profile,
                enabled = commands.has_selected_profile,
            },
            change_build_directory = {
                name = 'Change build directory',
                fn = commands.change_build_directory,
                enabled = commands.has_selected_profile,
            },
        },
        statusline = require('neodo.project_type.cmake.statusline').statusline,
    }
end

return M
