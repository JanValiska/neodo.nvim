local M = {}

local settings = require 'neodo.settings'

M.register = function()
    settings.project_types.makefile = {
        name = "Makefile",
        patterns = { 'Makefile' },
        on_attach = function()
            -- TODO: parse makefile and create commands
        end,
    }
end
return M
