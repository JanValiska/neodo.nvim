local neodo = require('neodo')

local M = {}

M.has_project = function() return neodo.get_project() ~= nil end

M.has_config = function() return neodo.has_config() end

M.project_statusline = function()
    local project = neodo.get_project()
    if project and project.statusline then
        if type(project.statusline) == 'function' then
            return project.statusline({ project = project })
        elseif type(project.statusline) == 'string' then
            return project.statusline
        end
    end
    return nil
end

M.project_type_statuslines = function()
    local lines = {}
    local project = neodo.get_project()
    if not project then return nil end
    local project_types = project:get_project_types()
    for key, project_type in pairs(project_types) do
        if type(project_type.statusline) == 'function' then
            lines[key] = project_type.statusline({ project = project, project_type = project_type })
        elseif type(project_type.statusline) == 'string' then
            lines[key] = project_type.statusline
        end
    end
    return lines
end

return M
