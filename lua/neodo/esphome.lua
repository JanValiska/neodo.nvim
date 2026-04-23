local M = {}

local notify = require('neodo.notify')

--- Scan directory for ESPHome YAML config files (excludes secrets.yaml)
local function find_configs(dir)
    local configs = {}
    local data = vim.loop.fs_scandir(dir)
    if not data then return configs end
    while true do
        local name, ftype = vim.loop.fs_scandir_next(data)
        if not name then break end
        if (ftype == 'file' or ftype == 'link') and name:match('%.yaml$') and name ~= 'secrets.yaml' then
            table.insert(configs, name)
        end
    end
    table.sort(configs)
    return configs
end

--- Rewrite esphome.active field in .neodo.lua
local function write_active_config(config_path, new_active)
    if vim.fn.filereadable(config_path) ~= 1 then return false end

    local lines = vim.fn.readfile(config_path)
    local in_esphome = false
    local found = false

    for i, line in ipairs(lines) do
        if line:match('^%s*esphome%s*=') then in_esphome = true end
        if in_esphome and line:match('^%s*active%s*=') then
            local indent = line:match('^(%s*)')
            lines[i] = indent .. 'active = "' .. new_active .. '",'
            found = true
            break
        end
        if in_esphome and line:match('^%s*},') then break end
    end

    if not found then return false end

    vim.fn.writefile(lines, config_path)
    return true
end

--- Generate default config lines for esphome project
function M.default_config_lines()
    return {
        '  esphome = {',
        '    -- active = "my_device.yaml",  -- device config to use, defaults to first found',
        '  },',
    }
end

--- Generate ESPHome commands
function M.commands(config, project_root, rebuild_commands_fn)
    local esphome_cfg = (config and config.esphome) or {}
    local cwd = esphome_cfg.src and (project_root .. '/' .. esphome_cfg.src) or project_root

    local all_configs = find_configs(cwd)
    if #all_configs == 0 then return {} end

    local active = esphome_cfg.active or all_configs[1]
    local suffix = #all_configs > 1 and (' (' .. active .. ')') or ''

    local cmds = {}

    local function cmd(subcmd, extra_args)
        local result = { 'esphome', subcmd, active }
        if extra_args then
            for _, a in ipairs(extra_args) do
                table.insert(result, a)
            end
        end
        return result
    end

    cmds.esphome_compile = {
        name = 'ESPHome: Compile' .. suffix,
        cmd = cmd('compile'),
        cwd = cwd,
    }

    cmds.esphome_upload = {
        name = 'ESPHome: Upload' .. suffix,
        cmd = cmd('upload'),
        cwd = cwd,
    }

    cmds.esphome_run = {
        name = 'ESPHome: Run (compile + upload + logs)' .. suffix,
        cmd = cmd('run'),
        cwd = cwd,
    }

    cmds.esphome_logs = {
        name = 'ESPHome: Logs' .. suffix,
        cmd = cmd('logs'),
        cwd = cwd,
    }

    cmds.esphome_clean = {
        name = 'ESPHome: Clean' .. suffix,
        cmd = cmd('clean'),
        cwd = cwd,
    }

    cmds.esphome_validate = {
        name = 'ESPHome: Validate config' .. suffix,
        cmd = cmd('config'),
        cwd = cwd,
    }

    if #all_configs > 1 then
        cmds.esphome_select_device = {
            name = 'ESPHome: Select device (' .. active .. ')',
            fn = function()
                local items = {}
                for _, cfg in ipairs(all_configs) do
                    table.insert(items, {
                        config = cfg,
                        label = cfg == active and (cfg .. ' (active)') or cfg,
                    })
                end
                vim.ui.select(items, {
                    prompt = 'Select ESPHome device',
                    format_item = function(item) return item.label end,
                }, function(selection)
                    if not selection then return end
                    local config_path = project_root .. '/.neodo.lua'
                    if not write_active_config(config_path, selection.config) then
                        notify.warning(
                            'Could not persist active device. Add `esphome = { active = "..." }` to .neodo.lua manually.'
                        )
                    end
                    config.esphome = config.esphome or {}
                    config.esphome.active = selection.config
                    notify.info('Device switched to: ' .. selection.config)
                    if rebuild_commands_fn then rebuild_commands_fn() end
                end)
            end,
        }
    end

    return cmds
end

return M
