local M = {}

local fs = require("neodo.file")

function M.get_selected_profile(project)
    local profile_key = project.config.selected_profile
    if not profile_key then
        return nil
    end
    return project.config.profiles[profile_key]
end

function M.switch_compile_commands(profile)
    if profile.configured then
        if fs.file_exists("compile_commands.json") then
            fs.delete("compile_commands.json")
        end
        fs.symlink(profile.build_dir .. "/compile_commands.json", "compile_commands.json")
    end
end

return M
