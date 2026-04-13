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

local function has_conan(project_root, source_dir)
    local dirs = { project_root }
    if source_dir then table.insert(dirs, project_root .. '/' .. source_dir) end
    for _, dir in ipairs(dirs) do
        if
            vim.fn.filereadable(dir .. '/conanfile.txt') == 1
            or vim.fn.filereadable(dir .. '/conanfile.py') == 1
        then
            return true
        end
    end
    return false
end

--- Return build_dir as-is (relative paths resolve against cwd which is project root)
local function resolve_build_dir(profile) return profile.build_dir end

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
local function configure_cmd(profile, project_root, source_dir)
    local build_dir = resolve_build_dir(profile)

    local cmd = { 'cmake', '-B', build_dir }

    if source_dir then
        table.insert(cmd, '-S')
        table.insert(cmd, source_dir)
    end

    table.insert(cmd, '-DCMAKE_EXPORT_COMPILE_COMMANDS=1')

    if profile.build_type then table.insert(cmd, '-DCMAKE_BUILD_TYPE=' .. profile.build_type) end

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
    if profile.conan and has_conan(project_root, source_dir) then
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
local function conan_install_cmd(profile, project_root, source_dir)
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

    table.insert(cmd, source_dir or '.')

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

--- Ensure cmake file API query exists so configure generates target metadata
local function ensure_file_api_query(build_dir)
    local query_dir = build_dir .. '/.cmake/api/v1/query'
    vim.fn.mkdir(query_dir, 'p')
    local query_file = query_dir .. '/codemodel-v2'
    if vim.fn.filereadable(query_file) ~= 1 then vim.fn.writefile({}, query_file) end
end

--- Parse targets from cmake file API reply directory
local function parse_file_api_targets(build_dir)
    local reply_dir = build_dir .. '/.cmake/api/v1/reply'

    -- Find the codemodel reply file
    local codemodel_file = nil
    local files = vim.fn.glob(reply_dir .. '/codemodel-v2-*.json', false, true)
    if #files == 0 then return nil end
    codemodel_file = files[#files]

    local ok, codemodel = pcall(function()
        local content = vim.fn.readfile(codemodel_file)
        return vim.json.decode(table.concat(content, '\n'))
    end)
    if not ok or not codemodel then return nil end

    local targets = {}
    local configs = codemodel.configurations or {}
    -- Use first configuration (or the only one for single-config generators)
    local cfg = configs[1]
    if not cfg or not cfg.targets then return nil end

    for _, tgt in ipairs(cfg.targets) do
        -- Read individual target JSON for type info
        local target_file = reply_dir .. '/' .. tgt.jsonFile
        local tok, target_data = pcall(function()
            local tc = vim.fn.readfile(target_file)
            return vim.json.decode(table.concat(tc, '\n'))
        end)
        if tok and target_data then
            local ttype = target_data.type
            if
                ttype == 'EXECUTABLE'
                or ttype == 'STATIC_LIBRARY'
                or ttype == 'SHARED_LIBRARY'
                or ttype == 'MODULE_LIBRARY'
                or ttype == 'OBJECT_LIBRARY'
            then
                table.insert(targets, {
                    name = target_data.name,
                    type = ttype,
                })
            end
        end
    end

    table.sort(targets, function(a, b) return a.name < b.name end)
    return targets
end

--- Write a field value in the active profile section of .neodo.lua
local function write_profile_field(config_path, profile_key, field, value)
    if vim.fn.filereadable(config_path) ~= 1 then return false end

    local lines = vim.fn.readfile(config_path)
    local in_profiles = false
    local in_target_profile = false
    local found = false

    for i, line in ipairs(lines) do
        if line:match('^%s*profiles%s*=') then in_profiles = true end
        if in_profiles and line:match('^%s*' .. profile_key .. '%s*=') then
            in_target_profile = true
        end
        if in_target_profile and line:match('^%s*' .. field .. '%s*=') then
            local indent = line:match('^(%s*)')
            if value then
                lines[i] = indent .. field .. ' = "' .. value .. '",'
            else
                table.remove(lines, i)
            end
            found = true
            break
        end
        -- Insert field after build_dir line if not found before profile closes
        if in_target_profile and line:match('^%s*build_dir%s*=') and not found then
            -- Check if field exists further in this profile
            local has_field = false
            for j = i + 1, #lines do
                if lines[j]:match('^%s*' .. field .. '%s*=') then
                    has_field = true
                    break
                end
                if lines[j]:match('^%s*},') then break end
            end
            if not has_field and value then
                local indent = line:match('^(%s*)')
                table.insert(lines, i + 1, indent .. field .. ' = "' .. value .. '",')
                found = true
                break
            end
        end
    end

    if not found then return false end

    vim.fn.writefile(lines, config_path)
    return true
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
    table.insert(lines, '  -- src = "src",  -- path to CMakeLists.txt if not in project root')
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

--- Generate commented-out cmake config lines as a hint for manual setup
function M.commented_config_lines()
    local lines = {}
    table.insert(lines, '  -- CMake project (uncomment to enable):')
    table.insert(lines, '  -- src = "src",  -- path to CMakeLists.txt if not in project root')
    table.insert(lines, '  -- active = "default",')
    table.insert(lines, '  -- profiles = {')
    table.insert(lines, '  --   default = {')
    table.insert(lines, '  --     build_dir = "build",')
    table.insert(lines, '  --     build_type = "Debug",')
    table.insert(lines, '  --     cmake_options = {},')
    table.insert(lines, '  --     build_args = {},')
    table.insert(lines, '  --   },')
    table.insert(lines, '  -- },')
    return lines
end

--- Generate cmake commands from config and return them
--- Also returns on_load callback and select_profile command
function M.commands(config, project_root, rebuild_commands_fn)
    local profile = get_active_profile(config)
    if not profile then return {} end

    local source_dir = config.src

    local cmds = {}

    local build_dir = resolve_build_dir(profile)

    cmds.configure = {
        name = 'CMake: Configure',
        cmd = configure_cmd(profile, project_root, source_dir),
        cwd = project_root,
        errorformat = M.gcc_errorformat,
        on_success = function() switch_compile_commands(profile, project_root) end,
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

    if has_conan(project_root, source_dir) then
        cmds.conan_install = {
            name = 'CMake: Conan install',
            cmd = conan_install_cmd(profile, project_root, source_dir),
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
                    if key == config.active then label = key .. ' (active)' end
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

    -- Target selection command
    local type_labels = {
        EXECUTABLE = 'exe',
        STATIC_LIBRARY = 'static lib',
        SHARED_LIBRARY = 'shared lib',
        MODULE_LIBRARY = 'module lib',
        OBJECT_LIBRARY = 'object lib',
    }
    cmds.select_target = {
        name = 'CMake: Select target' .. (profile.target and (' (' .. profile.target .. ')') or ''),
        fn = function()
            local targets = parse_file_api_targets(build_dir)
            if not targets or #targets == 0 then
                -- Ensure query exists for next configure
                ensure_file_api_query(build_dir)
                notify.error('No targets found. Run configure first.')
                return
            end

            -- Mark current target
            local items = {}
            for _, t in ipairs(targets) do
                local label = t.name .. ' [' .. (type_labels[t.type] or t.type) .. ']'
                if t.name == profile.target then label = label .. ' (active)' end
                table.insert(items, { target = t.name, label = label })
            end

            vim.ui.select(items, {
                prompt = 'Select target',
                format_item = function(item) return item.label end,
            }, function(selection)
                if not selection then return end
                profile.target = selection.target
                local config_path = project_root .. '/.neodo.lua'
                local active_key = config.active or vim.tbl_keys(config.profiles)[1]
                write_profile_field(config_path, active_key, 'target', selection.target)
                notify.info('Target set to: ' .. selection.target)
                if rebuild_commands_fn then rebuild_commands_fn() end
            end)
        end,
    }

    return cmds
end

--- Called when project is loaded - switch compile_commands for active profile
function M.on_load(config, project_root)
    local profile = get_active_profile(config)
    if profile then
        switch_compile_commands(profile, project_root)
        ensure_file_api_query(resolve_build_dir(profile))
    end
end

return M
