local M = {}

function M.statusline(project)
    local statusline = "CMake ❯ "
    if project.config.selected_profile then
        statusline = statusline .. project.config.selected_profile
        local profile = project.config.profiles[project.config.selected_profile]
        if not profile.configured then
            statusline = statusline .. " ❯ unconfigured"
        else
            if project.config.selected_target then
                statusline = statusline .. " ❯ " .. project.config.selected_target
            end
        end
    else
        statusline = statusline .. "no profile"
    end
    return statusline
end

return M
