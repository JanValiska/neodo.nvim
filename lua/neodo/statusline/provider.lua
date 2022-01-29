local runner = require'neodo.runner'

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

local function add_jobs_status(statusline)
    local jobs = runner.get_jobs_count()
    if jobs ~= 0 then
        return statusline .. ' Running: ' .. tostring(jobs)
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

            if project == nil then
                return ''
            end

            local statusline = ' '
            if project.statusline and type(project.statusline) == 'function' then
                statusline = statusline .. project.statusline(project)
            else
                statusline = statusline .. (project.name or project.type or 'Generic')
            end
            statusline = add_jobs_status(statusline)
            return statusline
        end
    end
    return ''
end

return M
