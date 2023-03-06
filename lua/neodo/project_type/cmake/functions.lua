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
        local root = Path:new(profile:get_project_path(), 'compile_commands.json')
        local build = Path:new(profile:get_build_dir(), 'compile_commands.json')
        local cwd = vim.loop.cwd()
        if root:exists() then root:rm() end
        uv.fs_symlink(build:make_relative(cwd), root:make_relative(cwd))
    end
end

return M
