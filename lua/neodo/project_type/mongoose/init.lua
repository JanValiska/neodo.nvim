local M = {}

local utils = require 'neodo.utils'
local settings = require 'neodo.settings'
local compilers = require("neodo.compilers")
local log = require("neodo.log")

function M.build_cmd(params, _)
    local cmd = { 'mos build' }

    if not params then return { type = 'error', text = 'Params not found' } end

    -- Check platform param
    if params.platform == nil then
        log.error("Parameter '--platform' missing", "Mongoose OS")
        return nil
    else
        table.insert(cmd, "--platform " .. params.platform)
    end

    if params.local_build then table.insert(cmd, "--local") end

    if params.verbose then table.insert(cmd, "--verbose") end

    if params.port then table.insert(cmd, "--port " .. params.port) end

    return utils.tbl_join(cmd, ' ')
end

M.build_params = { platform = "esp32", local_build = true, verbose = false }

M.build_errorformat = compilers.get_errorformat('gcc')


function M.flash_cmd(params, _)
    local cmd = { 'mos flash' }

    if params ~= nil then
        if params.port then table.insert(cmd, "--port " .. params.port) end
    end

    return utils.tbl_join(cmd, ' ')
end

M.register = function()
    settings.project_types.mongoose = {
        name = "Mongoose OS",
        commands = {
            build = {
                name = "Build",
                cmd = M.build_cmd,
                params = M.build_params,
                errorformat = M.build_errorformat
            },
            flash = { name = "Flash", cmd = M.flash_cmd }
        },
        patterns = { 'mos.yml' },
        on_attach = nil,
        buffer_on_attach = nil,
        user_buffer_on_attach = nil,
    }
end

return M
