local M = {}

local uv = vim.loop
local Path = require('plenary.path')

function M.get_selected_profile(project)
    local profile_key = project.config.selected_profile
    if not profile_key then return nil end
    return project.config.profiles[profile_key]
end

function M.switch_compile_commands(profile)
    if profile:is_configured() then
        local src_compile_commands = Path:new(profile:get_source_dir(), 'compile_commands.json')
        local build_compile_commands = Path:new(profile:get_build_dir(), 'compile_commands.json')
        if src_compile_commands:exists() then src_compile_commands:rm() end
        uv.fs_symlink(build_compile_commands, src_compile_commands)
    end
end

return M
