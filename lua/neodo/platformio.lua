local M = {}

local notify = require('neodo.notify')

--- Parse environments from a platformio.ini file (handles [env:xxx] sections and extra_configs)
local function parse_ini_envs(ini_path, seen)
    seen = seen or {}
    if seen[ini_path] then return {}, nil end
    seen[ini_path] = true

    if vim.fn.filereadable(ini_path) ~= 1 then return {}, nil end

    local envs = {}
    local default_env = nil
    local extra_configs = {}
    local current_section = nil
    local in_platformio_section = false
    local collecting_default_envs = false
    local collecting_extra_configs = false

    for _, raw in ipairs(vim.fn.readfile(ini_path)) do
        local line = raw:gsub(';.*$', ''):gsub('#.*$', '')

        local section = line:match('^%s*%[([^%]]+)%]')
        if section then
            current_section = section
            in_platformio_section = (section == 'platformio')
            collecting_default_envs = false
            collecting_extra_configs = false

            local env_name = section:match('^env:(.+)$')
            if env_name then
                env_name = env_name:gsub('%s+$', '')
                table.insert(envs, env_name)
            end
        else
            if in_platformio_section then
                local key, value = line:match('^%s*([%w_]+)%s*=%s*(.*)$')
                if key == 'default_envs' then
                    collecting_default_envs = true
                    collecting_extra_configs = false
                    if value and value ~= '' then default_env = value:match('^%s*([%w_-]+)') end
                elseif key == 'extra_configs' then
                    collecting_default_envs = false
                    collecting_extra_configs = true
                    if value and value ~= '' then
                        local cfg = value:match('^%s*(%S+)')
                        if cfg then table.insert(extra_configs, cfg) end
                    end
                elseif key then
                    collecting_default_envs = false
                    collecting_extra_configs = false
                elseif collecting_default_envs then
                    local val = line:match('^%s*([%w_-]+)')
                    if val and not default_env then default_env = val end
                elseif collecting_extra_configs then
                    local val = line:match('^%s*(%S+)')
                    if val then table.insert(extra_configs, val) end
                end
            end
        end
    end

    -- Follow extra_configs
    local base_dir = vim.fn.fnamemodify(ini_path, ':h')
    for _, cfg in ipairs(extra_configs) do
        local cfg_path = cfg:match('^/') and cfg or (base_dir .. '/' .. cfg)
        local sub_envs, sub_default = parse_ini_envs(cfg_path, seen)
        for _, e in ipairs(sub_envs) do
            table.insert(envs, e)
        end
        if not default_env then default_env = sub_default end
    end

    return envs, default_env
end

--- Resolve platformio working directory (where platformio.ini lives)
local function resolve_cwd(project_root, config)
    local pio = (config and config.platformio) or {}
    return pio.src and (project_root .. '/' .. pio.src) or project_root
end

--- Get list of environments and the active one
local function get_envs(project_root, config)
    local cwd = resolve_cwd(project_root, config)
    local ini_path = cwd .. '/platformio.ini'
    local envs, default_env = parse_ini_envs(ini_path)

    local pio = config.platformio or {}
    local active = pio.active or default_env or envs[1]

    return envs, active
end

--- Rewrite platformio.active field in .neodo.lua
local function write_active_env(config_path, new_active)
    if vim.fn.filereadable(config_path) ~= 1 then return false end

    local lines = vim.fn.readfile(config_path)
    local in_platformio = false
    local found = false

    for i, line in ipairs(lines) do
        if line:match('^%s*platformio%s*=') then in_platformio = true end
        if in_platformio and line:match('^%s*active%s*=') then
            local indent = line:match('^(%s*)')
            lines[i] = indent .. 'active = "' .. new_active .. '",'
            found = true
            break
        end
        if in_platformio and line:match('^%s*},') then break end
    end

    if not found then return false end

    vim.fn.writefile(lines, config_path)
    return true
end

--- Symlink compile_commands.json from .pio/build/<env> to project root
local function switch_compile_commands(project_root, config, env)
    if not env then return end

    local cwd = resolve_cwd(project_root, config)
    local source = cwd .. '/.pio/build/' .. env .. '/compile_commands.json'
    local target = cwd .. '/compile_commands.json'

    if vim.fn.filereadable(source) ~= 1 then return end

    vim.fn.delete(target)
    vim.loop.fs_symlink(source, target)
end

--- Generate default config lines for platformio project
function M.default_config_lines()
    local lines = {}
    table.insert(lines, '  platformio = {')
    table.insert(
        lines,
        '    -- src = "firmware",  -- path to platformio.ini if not in project root'
    )
    table.insert(
        lines,
        '    -- active = "my_env",  -- from platformio.ini, defaults to default_envs or first [env:...]'
    )
    table.insert(lines, '    -- envs = {')
    table.insert(lines, '    --   my_env = {')
    table.insert(
        lines,
        '    --     upload_delay = 10,  -- seconds to wait before upload (for bootloader mode)'
    )
    table.insert(lines, '    --     upload_port = "/dev/ttyUSB0",  -- override upload port')
    table.insert(lines, '    --   },')
    table.insert(lines, '    -- },')
    table.insert(lines, '  },')
    return lines
end

--- Generate platformio commands
function M.commands(config, project_root, rebuild_commands_fn)
    local envs, active = get_envs(project_root, config)
    if #envs == 0 then return {} end

    local pio = config.platformio or {}
    local env_cfg = (pio.envs and active and pio.envs[active]) or {}
    local pio_cwd = resolve_cwd(project_root, config)

    local cmds = {}

    local function pio_cmd(args)
        local cmd = { 'pio' }
        for _, a in ipairs(args) do
            table.insert(cmd, a)
        end
        return cmd
    end

    local function with_env(args)
        local result = {}
        for _, a in ipairs(args) do
            table.insert(result, a)
        end
        if active then
            table.insert(result, '-e')
            table.insert(result, active)
        end
        return result
    end

    cmds.build = {
        name = 'PIO: Build' .. (active and (' (' .. active .. ')') or ''),
        cmd = pio_cmd(with_env({ 'run' })),
        cwd = pio_cwd,
    }

    cmds.upload = {
        name = 'PIO: Upload' .. (active and (' (' .. active .. ')') or ''),
        cmd = pio_cmd(with_env({ 'run', '-t', 'upload' })),
        cwd = pio_cwd,
    }

    -- Delayed upload (useful for bootloader activation)
    if env_cfg.upload_delay and env_cfg.upload_delay > 0 then
        local delay = env_cfg.upload_delay
        cmds.upload_delayed = {
            name = 'PIO: Upload in ' .. delay .. 's' .. (active and (' (' .. active .. ')') or ''),
            cmd = {
                'sh',
                '-c',
                'echo "Waiting '
                    .. delay
                    .. 's before upload..."; sleep '
                    .. delay
                    .. ' && pio run -t upload'
                    .. (active and (' -e ' .. active) or ''),
            },
            cwd = pio_cwd,
        }
    end

    cmds.clean = {
        name = 'PIO: Clean' .. (active and (' (' .. active .. ')') or ''),
        cmd = pio_cmd(with_env({ 'run', '-t', 'clean' })),
        cwd = pio_cwd,
    }

    cmds.monitor = {
        name = 'PIO: Monitor' .. (active and (' (' .. active .. ')') or ''),
        cmd = pio_cmd(with_env({ 'device', 'monitor' })),
        cwd = pio_cwd,
    }

    cmds.test = {
        name = 'PIO: Test' .. (active and (' (' .. active .. ')') or ''),
        cmd = pio_cmd(with_env({ 'test' })),
        cwd = pio_cwd,
    }

    cmds.upload_fs = {
        name = 'PIO: Upload filesystem' .. (active and (' (' .. active .. ')') or ''),
        cmd = pio_cmd(with_env({ 'run', '-t', 'uploadfs' })),
        cwd = pio_cwd,
    }

    cmds.compiledb = {
        name = 'PIO: Generate compile_commands.json',
        cmd = pio_cmd(with_env({ 'run', '-t', 'compiledb' })),
        cwd = project_root,
        on_success = function() switch_compile_commands(project_root, config, active) end,
    }

    cmds.device_list = {
        name = 'PIO: Device list',
        cmd = { 'pio', 'device', 'list' },
        cwd = pio_cwd,
    }

    cmds.pkg_update = {
        name = 'PIO: Update packages',
        cmd = { 'pio', 'pkg', 'update' },
        cwd = pio_cwd,
    }

    -- Environment selection
    if #envs > 1 then
        cmds.select_env = {
            name = 'PIO: Select env (' .. (active or '?') .. ')',
            fn = function()
                local items = {}
                for _, e in ipairs(envs) do
                    local label = e
                    if e == active then label = e .. ' (active)' end
                    table.insert(items, { env = e, label = label })
                end
                vim.ui.select(items, {
                    prompt = 'Select environment',
                    format_item = function(item) return item.label end,
                }, function(selection)
                    if not selection then return end

                    -- Ensure config file has platformio.active
                    local config_path = project_root .. '/.neodo.lua'
                    if not write_active_env(config_path, selection.env) then
                        notify.warning(
                            'Could not persist active env. Add `platformio = { active = "..." }` to .neodo.lua manually.'
                        )
                    end

                    config.platformio = config.platformio or {}
                    config.platformio.active = selection.env
                    switch_compile_commands(project_root, config, selection.env)
                    notify.info('Env switched to: ' .. selection.env)
                    if rebuild_commands_fn then rebuild_commands_fn() end
                end)
            end,
        }
    end

    return cmds
end

--- Called when project is loaded
function M.on_load(config, project_root)
    local _, active = get_envs(project_root, config)
    if active then switch_compile_commands(project_root, config, active) end
end

return M
