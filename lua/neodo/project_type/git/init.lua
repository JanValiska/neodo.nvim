local M = {}

M.register = function()
    local settings = require("neodo.settings")
    settings.project_types.git = {
        name = "Git",
        patterns = { ".git" },
        commands = {
            neogit = {
                fn = function() vim.cmd("Neogit") end
            }
        }
    }
end

return M
