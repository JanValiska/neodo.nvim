local M = {}

local utils = require 'neodo.utils'
local settings = require 'neodo.settings'
local log = require 'neodo.log'

M.register = function()
    settings.project_type.php_composer = {
        name = "PHP(composer)",
        commands = {
        },
        patterns = {'composer.json'},
        on_attach = nil,
        buffer_on_attach = nil,
        user_buffer_on_attach = nil,
    }
end

return M
