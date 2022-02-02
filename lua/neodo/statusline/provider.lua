local runner = require'neodo.runner'
local utils = require'neodo.utils'

local M = function()
    local buf = vim.api.nvim_win_get_buf(0)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = utils.get_buf_variable(buf, "neodo_project_hash")
        if hash ~= nil then
            local neodo = require 'neodo'
            local project = neodo.get_project(hash)

            if project == nil then
                return ''
            end

            local statusline = ' '
            if project.statusline and type(project.statusline) == 'function' then
                statusline = statusline .. project.statusline(project)
            else
                statusline = statusline .. (project.name or project.type or 'Generic')
            end
            return statusline
        end
    end
    return ''
end

return M
