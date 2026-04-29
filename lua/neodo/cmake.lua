local M = {}

local notify = require('neodo.notify')
local conan_mod = require('neodo.conan')

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
local function configure_cmd(profile, effective_conan, source_dir)
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
    if next(effective_conan) ~= nil then
        local ver = conan_mod.detect_version()
        if ver and ver >= 2 then
            local conan_libs = build_dir .. '/conan_libs'
            -- cmake_layout puts generators under build/<BuildType>/generators/
            local found =
                vim.fn.glob(conan_libs .. '/build/*/generators/conan_toolchain.cmake', false, true)
            local toolchain = #found > 0 and found[1] or (conan_libs .. '/conan_toolchain.cmake')
            table.insert(cmd, '-DCMAKE_TOOLCHAIN_FILE=' .. toolchain)
        end
    end

    return cmd
end

--- Build cmake build command from profile settings
local function build_cmd(profile, _, target)
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
local function clean_cmd(profile)
    local build_dir = resolve_build_dir(profile)
    return { 'cmake', '--build', build_dir, '--target', 'clean' }
end

local cmake_internal_targets = {
    all = true,
    clean = true,
    CLEAN = true,
    depend = true,
    cmake_check_build_system = true,
    rebuild_cache = true,
    edit_cache = true,
    Makefile = true,
}

--- Parse phony targets from build.ninja
local function parse_ninja_targets(build_dir)
    local ninja_file = build_dir .. '/build.ninja'
    if vim.fn.filereadable(ninja_file) ~= 1 then return nil end

    local targets = {}
    for _, line in ipairs(vim.fn.readfile(ninja_file)) do
        local name, rule = line:match('^build ([^:]+): (%S+)')
        if name and rule == 'phony' and not cmake_internal_targets[name] then
            table.insert(targets, name)
        end
    end
    table.sort(targets)
    return targets
end

--- Parse .PHONY targets from top-level Makefile
local function parse_makefile_targets(build_dir)
    local makefile_path = build_dir .. '/Makefile'
    if vim.fn.filereadable(makefile_path) ~= 1 then return nil end

    local seen = {}
    local targets = {}
    for _, line in ipairs(vim.fn.readfile(makefile_path)) do
        local rest = line:match('^%.PHONY%s*:%s*(.+)$')
        if rest then
            for name in rest:gmatch('%S+') do
                if not cmake_internal_targets[name] and not seen[name] then
                    seen[name] = true
                    table.insert(targets, name)
                end
            end
        end
    end
    table.sort(targets)
    return targets
end

--- Try ninja first, fall back to makefile
local function parse_build_targets(build_dir)
    return parse_ninja_targets(build_dir) or parse_makefile_targets(build_dir)
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

--- Get cmake sub-config
local function get_cmake_config(config) return (config and config.cmake) or {} end

--- Get the active profile from config
local function get_active_profile(config)
    local cc = get_cmake_config(config)
    if not cc.profiles then return nil end
    local key = cc.active
    if not key then
        local keys = vim.tbl_keys(cc.profiles)
        if #keys == 1 then
            key = keys[1]
        else
            return nil
        end
    end
    return cc.profiles[key], key
end

--- Ensure cmake file API query exists so configure generates target metadata
local function ensure_file_api_query(build_dir)
    local query_dir = build_dir .. '/.cmake/api/v1/query'
    vim.fn.mkdir(query_dir, 'p')
    local query_file = query_dir .. '/codemodel-v2'
    if vim.fn.filereadable(query_file) ~= 1 then vim.fn.writefile({}, query_file) end
end

--- Detect ccache usage and extract CCACHE_DIR from CMakeCache.txt / launcher script
--- Returns { used = bool, ccache_dir = string|nil }
local function detect_ccache(build_dir)
    local result = { used = false, ccache_dir = nil }
    local cache_file = build_dir .. '/CMakeCache.txt'
    if vim.fn.filereadable(cache_file) ~= 1 then return result end

    local launcher = nil
    for _, line in ipairs(vim.fn.readfile(cache_file)) do
        local value = line:match('^CMAKE_[CX]+_COMPILER_LAUNCHER[^=]*=(.*)$')
        if value and value:match('ccache') then
            result.used = true
            launcher = value
            break
        end
    end

    if not result.used then return result end

    -- If launcher points to a script file, extract CCACHE_DIR assignment
    if launcher and vim.fn.filereadable(launcher) == 1 then
        for _, line in ipairs(vim.fn.readfile(launcher)) do
            local dir = line:match('CCACHE_DIR=([^%s]+)')
            if dir then
                -- Strip quotes if present
                dir = dir:gsub('^["\']', ''):gsub('["\']$', '')
                result.ccache_dir = dir
                break
            end
        end
    end

    return result
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
                local artifact = nil
                if target_data.artifacts and target_data.artifacts[1] then
                    artifact = target_data.artifacts[1].path
                end
                table.insert(targets, {
                    name = target_data.name,
                    type = ttype,
                    artifact = artifact,
                })
            end
        end
    end

    table.sort(targets, function(a, b) return a.name < b.name end)
    return targets
end

--- Write a field value in the active profile section of .neodo.lua (within cmake = { profiles = { ... } })
local function write_profile_field(config_path, profile_key, field, value)
    if vim.fn.filereadable(config_path) ~= 1 then return false end

    local lines = vim.fn.readfile(config_path)
    local in_cmake = false
    local in_profiles = false
    local in_target_profile = false
    local found = false

    for i, line in ipairs(lines) do
        if line:match('^%s*cmake%s*=') then in_cmake = true end
        if in_cmake and line:match('^%s*profiles%s*=') then in_profiles = true end
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

--- Rewrite the cmake.active field in .neodo.lua config file
local function write_active_profile(config_path, new_active)
    if vim.fn.filereadable(config_path) ~= 1 then return false end

    local lines = vim.fn.readfile(config_path)
    local in_cmake = false
    local found = false
    for i, line in ipairs(lines) do
        if line:match('^%s*cmake%s*=') then in_cmake = true end
        if in_cmake and line:match('^%s*active%s*=') then
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
function M.default_config_lines()
    local lines = {}
    table.insert(lines, '  cmake = {')
    table.insert(lines, '    -- src = "src",  -- path to CMakeLists.txt if not in project root')
    table.insert(lines, '    active = "default",')
    table.insert(lines, '')
    table.insert(lines, '    profiles = {')
    table.insert(lines, '      default = {')
    table.insert(lines, '        build_dir = "build",')
    table.insert(lines, '        build_type = "Debug",')
    table.insert(lines, '        cmake_options = {},')
    table.insert(lines, '        build_args = {},')
    table.insert(
        lines,
        '        -- conan = { profile = "other" },  -- overrides top-level conan config'
    )
    table.insert(lines, '        -- targets = {')
    table.insert(lines, '        --   my_target = { cwd = "data", args = { "--verbose" } },')
    table.insert(lines, '        -- },')
    table.insert(lines, '      },')
    table.insert(lines, '    },')
    table.insert(lines, '  },')
    return lines
end

--- Generate commented-out cmake config lines as a hint for manual setup
function M.commented_config_lines()
    local lines = {}
    table.insert(lines, '  -- CMake project (uncomment to enable):')
    table.insert(lines, '  -- cmake = {')
    table.insert(lines, '  --   src = "src",  -- path to CMakeLists.txt if not in project root')
    table.insert(lines, '  --   active = "default",')
    table.insert(lines, '  --   profiles = {')
    table.insert(lines, '  --     default = {')
    table.insert(lines, '  --       build_dir = "build",')
    table.insert(lines, '  --       build_type = "Debug",')
    table.insert(lines, '  --       cmake_options = {},')
    table.insert(lines, '  --       build_args = {},')
    table.insert(lines, '  --     },')
    table.insert(lines, '  --   },')
    table.insert(lines, '  -- },')
    return lines
end

--- Generate cmake commands from config and return them
--- Also returns on_load callback and select_profile command
function M.commands(config, project_root, rebuild_commands_fn)
    local profile, active_profile_key = get_active_profile(config)
    if not profile then return {} end

    local cc = get_cmake_config(config)
    local source_dir = cc.src

    -- Merge top-level conan config with profile-level override
    local effective_conan = vim.tbl_extend('force', config.conan or {}, profile.conan or {})

    local cmds = {}

    local build_dir = resolve_build_dir(profile)

    cmds.configure = {
        name = 'CMake: Configure',
        cmd = configure_cmd(profile, effective_conan, source_dir),
        cwd = project_root,
        errorformat = M.gcc_errorformat,
        on_success = function()
            switch_compile_commands(profile, project_root)
            if rebuild_commands_fn then rebuild_commands_fn() end
        end,
    }

    cmds.build = {
        name = 'CMake: Build all',
        cmd = build_cmd(profile),
        cwd = project_root,
        errorformat = M.gcc_errorformat,
    }

    if profile.target then
        cmds.build_target = {
            name = 'CMake: Build ' .. profile.target,
            cmd = build_cmd(profile, nil, profile.target),
            cwd = project_root,
            errorformat = M.gcc_errorformat,
        }

        -- Run target command - find executable path via file API
        local targets = parse_file_api_targets(build_dir)
        local target_info = nil
        if targets then
            for _, t in ipairs(targets) do
                if t.name == profile.target then
                    target_info = t
                    break
                end
            end
        end

        if target_info and target_info.type == 'EXECUTABLE' and target_info.artifact then
            local target_cfg = (profile.targets and profile.targets[profile.target]) or {}
            local exe_path = project_root .. '/' .. build_dir .. '/' .. target_info.artifact
            local run_cwd = target_cfg.cwd
            if run_cwd then
                -- Relative to project root
                if not run_cwd:match('^/') then run_cwd = project_root .. '/' .. run_cwd end
            else
                run_cwd = project_root
            end

            local run_cmd = { exe_path }
            if target_cfg.args then
                for _, a in ipairs(target_cfg.args) do
                    table.insert(run_cmd, a)
                end
            end

            cmds.run_target = {
                name = 'CMake: Run ' .. profile.target,
                cmd = run_cmd,
                cwd = run_cwd,
            }
        end
    end

    cmds.clean = {
        name = 'CMake: Clean',
        cmd = clean_cmd(profile),
        cwd = project_root,
    }

    local ccache = detect_ccache(build_dir)
    if ccache.used then
        local clear_cmd
        if ccache.ccache_dir then
            clear_cmd = { 'env', 'CCACHE_DIR=' .. ccache.ccache_dir, 'ccache', '--clear' }
        else
            clear_cmd = { 'ccache', '--clear' }
        end
        cmds.ccache_clear = {
            name = 'CMake: Clear ccache',
            cmd = clear_cmd,
            cwd = project_root,
            notify = true,
        }
    end

    if conan_mod.has_conanfile(project_root, source_dir) or next(effective_conan) ~= nil then
        cmds.conan_install = {
            name = 'CMake: Conan install',
            cmd = conan_mod.build_install_cmd(effective_conan, source_dir, build_dir),
            cwd = project_root,
            notify = true,
        }
    end

    -- Add commands for parsed build system targets (after configure)
    local parsed_targets = parse_build_targets(build_dir)
    if parsed_targets then
        for _, target in ipairs(parsed_targets) do
            if target ~= profile.target then
                local key = 'cmake_target_' .. target:gsub('[^%w]', '_')
                cmds[key] = {
                    name = 'CMake: ' .. target,
                    cmd = build_cmd(profile, nil, target),
                    cwd = project_root,
                    errorformat = M.gcc_errorformat,
                }
            end
        end
    end

    -- Profile selection command
    if cc.profiles and vim.tbl_count(cc.profiles) > 1 then
        local active_key = cc.active or '?'
        cmds.select_profile = {
            name = 'Select profile (' .. active_key .. ')',
            fn = function()
                local items = {}
                for key, p in pairs(cc.profiles) do
                    local label = key
                    if key == cc.active then label = key .. ' (active)' end
                    table.insert(items, { key = key, label = label, profile = p })
                end
                table.sort(items, function(a, b) return a.key < b.key end)
                vim.ui.select(items, {
                    prompt = 'Select profile',
                    format_item = function(item) return item.label end,
                }, function(selection)
                    if not selection then return end
                    config.cmake = config.cmake or {}
                    config.cmake.active = selection.key
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
                local active_key = active_profile_key
                    or (cc.profiles and vim.tbl_keys(cc.profiles)[1])
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
