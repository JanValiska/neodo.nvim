local log = require('neodo.log')
local notify = require('neodo.notify')
local utils = require('neodo.utils')
local config = require('neodo.project_type.conan.config')
local commands = require('neodo.project_type.cmake.commands')

local M = {}

M.register = function()
    local settings = require('neodo.settings')
    settings.project_types.conan = {
        name = 'Conan',
        patterns = { 'conanfile.txt', 'conanfile.py' },
        on_attach = {
            function(ctx)
                log.debug("Conan on_attach called")
                local function load_config() config.load(ctx.project, ctx.project_type) end

                local function conan_version()
                    local lines = utils.get_output('conan --version')
                    local semver = utils.split_string(lines[1], ' ')[3]
                    return utils.split_string(semver, '.')[1]
                end

                local noerr, version_str = pcall(conan_version)
                ctx.project_type.conan_version = not noerr or tonumber(version_str)
                log.debug("Detected conan version", vim.inspect(ctx.project_type.conan_version))

                if not ctx.project:get_config_file() then
                    ctx.project:create_config_file(function(result)
                        if result then
                            load_config()
                        else
                            notify.error(
                                'Conan project type needs project data path, but that cannot be created.'
                            )
                        end
                    end)
                else
                    load_config()
                end
            end,
        },
        commands = {
            conan_install = commands.conan_install(),
            select_conan_profile = commands.select_conan_profile(),
        },
        get_info_node = function(_)
            return nil
        end,
    }
end

return M
