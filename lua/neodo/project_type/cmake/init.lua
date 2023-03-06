local M = {}

local notify = require('neodo.notify')
local config = require('neodo.project_type.cmake.config')
local commands = require('neodo.project_type.cmake.commands')
local log = require('neodo.log')
local Path = require('plenary.path')

M.register = function()
    local settings = require('neodo.settings')
    settings.project_types.cmake = {
        name = 'CMake',
        patterns = { 'CMakeLists.txt' },
        on_attach = {
            function(ctx)
                local function load_config() config.load(ctx.project, ctx.project_type) end
                local function any_of_exists(path, patterns)
                    log('Searching', vim.inspect(patterns), 'in', vim.inspect(path))
                    for _, pattern in ipairs(patterns) do
                        local exists = Path:new(path, pattern):exists()
                        if exists then return true end
                    end
                    return false
                end
                ctx.project_type.has_conan =
                    any_of_exists(ctx.project_type.path, { 'conanfile.txt', 'conanfile.py' })

                if not ctx.project:get_config_file() then
                    ctx.project:create_config_file(function(result)
                        if result then
                            load_config()
                        else
                            notify.error(
                                'CMake project_type needs project data_path, but cannot be created.'
                            )
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
            create_profile = commands.create_profile(),
            select_profile = commands.select_profile(),
            delete_profile = commands.delete_profile(),
            configure = commands.configure(),
            select_target = commands.select_target(),
            build_all = commands.build_all(),
            build_selected_target = commands.build_selected_target(),
            clean = commands.clean(),
            run_selected_target = commands.run_selected_target(),
            debug_selected_target = commands.debug_selected_target(),
            conan_install = commands.conan_install(),
            select_conan_profile = commands.select_conan_profile(),
            show_cache_variables = commands.show_cache_variables(),
            change_build_configuration = commands.change_build_configuration(),
            rename_profile = commands.rename_profile(),
            change_build_directory = commands.change_build_directory(),
        },
        statusline = require('neodo.project_type.cmake.statusline').statusline,
    }
end

return M
