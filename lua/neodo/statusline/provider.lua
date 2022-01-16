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

local function add_config_status(statusline, project)
    if not project.data_path then
        return statusline .. '(no config)'
    end
    return statusline
end

local M = function()
    local buf = vim.api.nvim_win_get_buf(0)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = get_buf_variable(buf, "neodo_project_hash")
        if hash ~= nil then
            local neodo = require 'neodo'
            local project = neodo.get_project(hash)

            local statusline = 'NeoDo/'
            if project.statusline and type(project.statusline) == 'function' then
                statusline = statusline .. project.statusline(project)
            else
                statusline = statusline .. (project.name or project.type or 'generic')
            end
            return add_config_status(statusline, project)
        end
    end
    return ''
end

return M
