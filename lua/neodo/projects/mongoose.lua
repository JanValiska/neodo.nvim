local M = {}

local utils = require 'neodo.utils'
local settings = require 'neodo.settings'
local log = require 'neodo.log'

function M.build_cmd(params)
    local cmd = {'mos build'}

    -- Check platform param
    if params.platform == nil then
        log("Platform not specified")
        return nil
    else
        table.insert(cmd, "--platform " .. params.platform)
    end

    if params.local_build then table.insert(cmd, "--local") end

    if params.port then table.insert(cmd, "--port " .. params.port) end

    return utils.tbl_join(cmd, ' ')
end

M.build_params = {platform = "esp32", local_build = true}

M.build_errorformat =
    [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]

function M.flash_cmd(params)
    local cmd = {'mos flash'}

    if params ~= nil then
        if params.port then table.insert(cmd, "--port " .. params.port) end
    end

    return utils.tbl_join(cmd, ' ')
end

M.register = function()
    settings.project_type.mongoose = {
        commands = {
            build = {
                type = 'terminal',
                name = "Build",
                cmd = M.build_cmd,
                params = M.build_params,
                errorformat = M.build_errorformat
            },
            flash = {type = 'terminal', name = "Flash", cmd = M.flash_cmd}
        },
        patterns = {'mos.yml'},
        on_attach = nil
    }
end

return M
