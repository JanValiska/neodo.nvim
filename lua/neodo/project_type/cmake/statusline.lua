local M = {}

function M.statusline(project_type)
    local statusline = "CMake ❯ "
    if project_type.config.selected_profile then
        statusline = statusline .. project_type.config.selected_profile
        local profile = project_type.config.profiles[project_type.config.selected_profile]
        if not profile.configured then
            statusline = statusline .. " ❯ unconfigured"
        else
            if project_type.config.selected_target then
                statusline = statusline .. " ❯ " .. project_type.config.selected_target
            end
        end
    else
        statusline = statusline .. "no profile"
    end
    return statusline
end

return M
