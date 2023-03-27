local M = {}

M.register = function()
    local settings = require('neodo.settings')
    settings.project_types.git = {
        name = 'Git',
        patterns = { '.git' },
        commands = {
            neogit = {
                name = "Show Neogit window",
                fn = function()
                    vim.cmd('Neogit')
                end,
            },
        },
        get_info_node = function(_)
            return nil
        end,
    }
end

return M
