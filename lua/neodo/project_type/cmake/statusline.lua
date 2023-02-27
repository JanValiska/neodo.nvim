local cmds = require('neodo.project_type.cmake.commands')
local M = {}

function M.statusline(ctx)
    local statusline = ''
    local profile = cmds.get_selected_profile(ctx)
    if profile then
        statusline = statusline .. " " .. profile:get_name()
        if profile:is_configured() then
            statusline = statusline .. '  '
            if profile:has_selected_target() then
                statusline = statusline .. profile:get_selected_target().name
            else
                statusline = statusline .. 'no target'
            end
        else
            statusline = statusline .. '   unconfigured'
        end
    else
        statusline = statusline .. '  no profile'
    end
    return statusline
end

return M
