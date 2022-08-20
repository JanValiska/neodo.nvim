local log = require('neodo.log')
local M = {}

local settings = require 'neodo.settings'

M.make_cmd = function(ctx)
    local args = ctx.params
    local cmd = "make"
    if type(args) == "table" then
        for _, arg in ipairs(args) do
            cmd = cmd .. " " .. arg
        end
    elseif type(args) == "string" then
        cmd = cmd .. " " .. args
    else
        log.warning("Unknown params type")
    end
    return cmd
end

M.register = function()
    settings.project_types.makefile = {
        name = "Makefile",
        patterns = { 'Makefile' },
        on_attach = function()
            -- TODO: parse makefile and create commands
        end,
        commands = {
            make = {
                cmd = M.make_cmd
            },
            make_all = {
                cmd = M.make_cmd,
                params = "all"
            }
        }
    }
end
return M
