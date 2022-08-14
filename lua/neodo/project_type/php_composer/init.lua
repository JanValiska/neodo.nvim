local M = {}

local settings = require 'neodo.settings'

M.register = function()
    settings.project_types.php_composer = {
        name = "PHP(composer)",
        commands = {
        },
        patterns = { 'composer.json' },
        on_attach = nil,
        buffer_on_attach = nil,
        user_buffer_on_attach = nil,
    }
end

return M
