local M = {}

M.register = function()
    local settings = require 'neodo.settings'
    local utils = require 'neodo.utils'
    local log = require 'neodo.log'
    settings.project_type.mongoose = {
        commands = {
            build = {
                type = 'terminal',
                name = "Build",
                cmd = function(params)
                    local cmd = {'mos build'}

                    -- Check platform param
                    if params.platform == nil then
                        log("Platform not specified")
                        return nil
                    else
                        table.insert(cmd, "--platform " .. params.platform)
                    end

                    if params.local_build then
                        table.insert(cmd, "--local")
                    end

                    return utils.tbl_join(cmd, ' ')
                end,
                params = {platform = "esp32", local_build = true},
                errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
            },
            flash = {
                type = 'terminal',
                name = "Flash",
                cmd = 'mos flash',
                errorformat = '%.%#'
            }
        },
        patterns = {'mos.yml'},
        on_attach = nil
    }
end

return M
