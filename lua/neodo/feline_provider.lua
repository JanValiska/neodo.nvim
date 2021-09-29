local function get_buf_variable(buf, var_name)
    local s, v = pcall(function()
        return vim.api.nvim_buf_get_var(buf, var_name)
    end)
    if s then
        return v
    else
        return nil
    end
end

local M = function(winid)
    local buf = vim.api.nvim_win_get_buf(winid)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = get_buf_variable(buf, "neodo_project_hash")
        if hash ~= nil then
            local neodo = require 'neodo'
            local project = neodo.get_project(hash)
            if project.statusline and type(project.statusline) == 'function' then
                return project.statusline(project)
            end
            local project_type = project.type or 'generic'
            local statusline = ' ' .. project_type
            if not project.data_path then
                statusline = statusline .. '(no config)'
            end
            return statusline
        end
    end
    return ''
end

return M
