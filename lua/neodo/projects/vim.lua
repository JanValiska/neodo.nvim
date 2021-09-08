local M = {}

M.register = function()
    local settings = require 'neodo.settings'
    settings.project_type.vim = {
        patterns = {'init.lua', 'init.vim'},
        on_attach = nil,
        commands = {
            packer_compile = {
                name = "Compile packer",
                type = 'function',
                cmd = function() require'packer'.compile() end
            }
        }
    }
end

return M
