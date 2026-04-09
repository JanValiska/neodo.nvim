local M = {}

local notify = require('neodo.notify')

-- Detect conan version once and cache
local conan_version = nil

local function detect_conan_version()
    if conan_version then return conan_version end
    local ok, lines = pcall(function()
        local output = vim.fn.system('conan --version')
        return vim.split(output, '\n')
    end)
    if not ok or not lines[1] then return nil end
    local ver = lines[1]:match('(%d+)%.')
    conan_version = ver and tonumber(ver) or nil
    return conan_version
end

local function has_conan(project_root)
    return vim.fn.filereadable(project_root .. '/conanfile.txt') == 1
        or vim.fn.filereadable(project_root .. '/conanfile.py') == 1
end

--- Return build_dir as-is (relative paths resolve against cwd which is project root)
local function resolve_build_dir(profile)
    return profile.build_dir
end

--- GCC errorformat for quickfix
M.gcc_errorformat = '%-G%f:%s:,'
    .. '%-G%f:%l: %#error: %#(Each undeclared identifier is reported only%.%#,'
    .. '%-G%f:%l: %#error: %#for each function it appears%.%#,'
    .. '%-GIn file included%.%#,'
    .. '%-G %#from %f:%l,'
    .. '%f:%l:%c: %trror: %m,'
    .. '%f:%l:%c: %tarning: %m,'
    .. '%I%f:%l:%c: note: %m,'
    .. '%f:%l:%c: %m,'
    .. '%f:%l: %trror: %m,'
    .. '%f:%l: %tarning: %m,'
    .. '%I%f:%l: note: %m,'
    .. '%f:%l: %m'

--- Build cmake configure command from profile settings
local function configure_cmd(profile, project_root)
    local build_dir = resolve_build_dir(profile)

    local cmd = { 'cmake', '-B', build_dir }
    table.insert(cmd, '-DCMAKE_EXPORT_COMPILE_COMMANDS=1')

    if profile.build_type then
        table.insert(cmd, '-DCMAKE_BUILD_TYPE=' .. profile.build_type)
    end

    if profile.generator then
        table.insert(cmd, '-G')
        table.insert(cmd, profile.generator)
    end

    if profile.cmake_options then
        for _, opt in ipairs(profile.cmake_options) do
            table.insert(cmd, opt)
        end
    end

    -- Conan v2 toolchain file
    if profile.conan and has_conan(project_root) then
        local ver = detect_conan_version()
        if ver and ver >= 2 then
            local toolchain = build_dir .. '/conan_libs/conan_toolchain.cmake'
            table.insert(cmd, '-DCMAKE_TOOLCHAIN_FILE=' .. toolchain)
        end
    end

    return cmd
end

--- Build cmake build command from profile settings
local function build_cmd(profile, project_root, target)
    local build_dir = resolve_build_dir(profile)

    local cmd = { 'cmake', '--build', build_dir }

    if target then
        table.insert(cmd, '--target')
        table.insert(cmd, target)
    end

    if profile.build_args then
        table.insert(cmd, '--')
        for _, arg in ipairs(profile.build_args) do
            table.insert(cmd, arg)
        end
    end

    return cmd
end

--- Build cmake clean command from profile settings
local function clean_cmd(profile, project_root)
    local build_dir = resolve_build_dir(profile)
    return { 'cmake', '--build', build_dir, '--target', 'clean' }
end

--- Build conan install command from profile settings (supports v1 and v2)
local function conan_install_cmd(profile, project_root)
    local build_dir = resolve_build_dir(profile)

    local ver = detect_conan_version()
    if not ver then
        notify.error('Conan not found or version detection failed')
        return nil
    end

    local cmd = { 'conan', 'install' }

    local conan = profile.conan or {}

    if conan.profile then
        if ver >= 2 then
            table.insert(cmd, '--profile:build=' .. conan.profile)
            table.insert(cmd, '--profile:host=' .. conan.profile)
        else
            table.insert(cmd, '--profile')
            table.insert(cmd, conan.profile)
        end
    end

    if conan.remote then
        table.insert(cmd, '-r')
        table.insert(cmd, conan.remote)
    end

    if conan.options then
        for _, opt in ipairs(conan.options) do
            table.insert(cmd, opt)
        end
    end

    table.insert(cmd, '.')

    if ver >= 2 then
        table.insert(cmd, '-of')
        table.insert(cmd, build_dir .. '/conan_libs')
    else
        table.insert(cmd, '-if')
        table.insert(cmd, build_dir)
    end

    return cmd
end

--- Symlink compile_commands.json from build dir to project root
local function switch_compile_commands(profile, project_root)
    local build_dir = resolve_build_dir(profile)

    local source = build_dir .. '/compile_commands.json'
    local target = project_root .. '/compile_commands.json'

    if vim.fn.filereadable(source) ~= 1 then return end

    vim.fn.delete(target)
    vim.loop.fs_symlink(source, target)
end

--- Get the active profile from config
local function get_active_profile(config)
    if not config or not config.profiles then return nil end
    local key = config.active
    if not key then
        local keys = vim.tbl_keys(config.profiles)
        if #keys == 1 then
            key = keys[1]
        else
            return nil
        end
    end
    return config.profiles[key], key
end

--- Rewrite the active field in .neodo.lua config file
local function write_active_profile(config_path, new_active)
    if vim.fn.filereadable(config_path) ~= 1 then return false end

    local lines = vim.fn.readfile(config_path)
    local found = false
    for i, line in ipairs(lines) do
        if line:match('^%s*active%s*=') then
            local indent = line:match('^(%s*)')
            lines[i] = indent .. 'active = "' .. new_active .. '",'
            found = true
            break
        end
    end

    if not found then return false end

    vim.fn.writefile(lines, config_path)
    return true
end

--- Generate default config lines for cmake project
function M.default_config_lines(has_conan_project)
    local lines = {}
    table.insert(lines, '  active = "default",')
    table.insert(lines, '')
    table.insert(lines, '  profiles = {')
    table.insert(lines, '    default = {')
    table.insert(lines, '      build_dir = "build",')
    table.insert(lines, '      build_type = "Debug",')
    table.insert(lines, '      cmake_options = {},')
    table.insert(lines, '      build_args = {},')
    if has_conan_project then
        table.insert(lines, '      conan = {')
        table.insert(lines, '        profile = "default",')
        table.insert(lines, '        -- remote = "my-remote",')
        table.insert(lines, '        -- options = { "--build=missing" },')
        table.insert(lines, '      },')
    end
    table.insert(lines, '    },')
    table.insert(lines, '  },')
    return lines
end

--- Generate cmake commands from config and return them
--- Also returns on_load callback and select_profile command
function M.commands(config, project_root, rebuild_commands_fn)
    local profile = get_active_profile(config)
    if not profile then return {} end

    local cmds = {}

    cmds.configure = {
        name = 'CMake: Configure',
        cmd = configure_cmd(profile, project_root),
        cwd = project_root,
        errorformat = M.gcc_errorformat,
        on_success = function()
            switch_compile_commands(profile, project_root)
        end,
    }

    cmds.build = {
        name = 'CMake: Build all',
        cmd = build_cmd(profile, project_root),
        cwd = project_root,
        errorformat = M.gcc_errorformat,
    }

    if profile.target then
        cmds.build_target = {
            name = 'CMake: Build ' .. profile.target,
            cmd = build_cmd(profile, project_root, profile.target),
            cwd = project_root,
            errorformat = M.gcc_errorformat,
        }
    end

    cmds.clean = {
        name = 'CMake: Clean',
        cmd = clean_cmd(profile, project_root),
        cwd = project_root,
    }

    if has_conan(project_root) then
        cmds.conan_install = {
            name = 'CMake: Conan install',
            cmd = conan_install_cmd(profile, project_root),
            cwd = project_root,
            notify = true,
        }
    end

    -- Profile selection command
    if config.profiles and vim.tbl_count(config.profiles) > 1 then
        local active_key = config.active or '?'
        cmds.select_profile = {
            name = 'Select profile (' .. active_key .. ')',
            fn = function()
                local items = {}
                for key, p in pairs(config.profiles) do
                    local label = key
                    if key == config.active then
                        label = key .. ' (active)'
                    end
                    table.insert(items, { key = key, label = label, profile = p })
                end
                table.sort(items, function(a, b) return a.key < b.key end)
                vim.ui.select(items, {
                    prompt = 'Select profile',
                    format_item = function(item) return item.label end,
                }, function(selection)
                    if not selection then return end
                    config.active = selection.key
                    local config_path = project_root .. '/.neodo.lua'
                    write_active_profile(config_path, selection.key)
                    switch_compile_commands(selection.profile, project_root)
                    notify.info('Profile switched to: ' .. selection.key)
                    if rebuild_commands_fn then rebuild_commands_fn() end
                end)
            end,
        }
    end

    return cmds
end

--- Called when project is loaded - switch compile_commands for active profile
function M.on_load(config, project_root)
    local profile = get_active_profile(config)
    if profile then
        switch_compile_commands(profile, project_root)
    end
end

return M
