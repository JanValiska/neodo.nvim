local utils = require 'neodo.utils'
local neodo = require 'neodo'

local M = function()
    local buf = vim.api.nvim_win_get_buf(0)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = utils.get_buf_variable(buf, "neodo_project_hash")
        if hash ~= nil then
            local project = neodo.get_project(hash)

            if project == nil then
                return ''
            end

            local statusline = ' '
            if project.statusline and type(project.statusline) == 'function' then
                statusline = statusline .. project.statusline(project)
            end
            local project_types = project.project_types()
            for _, project_type in pairs(project_types) do
                if project_type.statusline and type(project_type.statusline) == 'function' then
                    statusline = statusline .. project_type.statusline(project_type)
                else
                    statusline = statusline .. project_type.name
                end
                statusline = statusline .. ' '
            end
            return statusline
        end
    end
    return ''
end

return M
