local M = {}

local notify = require('neodo.notify')
local runner = require('neodo.runner')
local cmake = require('neodo.cmake')
local cargo = require('neodo.cargo')
local node = require('neodo.node')
local makefile = require('neodo.makefile')
local platformio = require('neodo.platformio')

--- Load and parse .neodo.lua config file
local function load_config(config_path)
    local ok, config = pcall(dofile, config_path)
    if not ok then
        notify.error('Failed to load ' .. config_path)
        return nil
    end
    return config or {}
end

--- Generate default .neodo.lua content for detected project types
local function generate_default_config(project_types)
    local has_conan = project_types.conan ~= nil
    local lines = { 'return {' }

    if project_types.cmake then
        vim.list_extend(lines, cmake.default_config_lines(has_conan))
    elseif project_types.platformio then
        vim.list_extend(lines, platformio.default_config_lines())
    else
        vim.list_extend(lines, cmake.commented_config_lines())
        table.insert(lines, '')
        if has_conan then
            table.insert(lines, '  commands = {')
            table.insert(lines, '    conan_install = "conan install . --build=missing",')
            table.insert(lines, '  },')
        end
    end

    table.insert(lines, '')
    table.insert(lines, '  -- commands = {')
    table.insert(lines, '  --   example = "echo hello",')
    table.insert(lines, '  -- },')
    table.insert(lines, '}')

    return table.concat(lines, '\n')
end

--- Create default .neodo.lua if it doesn't exist (auto-generated for cmake/conan only)
local function ensure_config(project_root, project_types)
    local config_path = project_root .. '/.neodo.lua'
    if vim.fn.filereadable(config_path) == 1 then return end

    if not project_types.cmake and not project_types.conan and not project_types.platformio then
        return
    end

    local content = generate_default_config(project_types)
    vim.fn.writefile(vim.split(content, '\n'), config_path)
    notify.info('Created default .neodo.lua', project_root)
end

--- Build command list for a project
local function build_commands(config, project_root, project_types)
    local commands = {}

    local function add(cmds)
        for key, cmd in pairs(cmds) do
            commands[key] = cmd
        end
    end

    -- Project type commands
    if project_types.cmake then
        local rebuild = function()
            local project = M.get(project_root)
            if project then
                project.commands = build_commands(config, project_root, project_types)
            end
        end
        add(cmake.commands(config, project_root, rebuild))
    end

    if project_types.platformio then
        local rebuild = function()
            local project = M.get(project_root)
            if project then
                project.commands = build_commands(config, project_root, project_types)
            end
        end
        add(platformio.commands(config, project_root, rebuild))
    end

    if project_types.rust then add(cargo.commands(config, project_root)) end

    if project_types.node then add(node.commands(config, project_root)) end

    if project_types.makefile then add(makefile.commands(config, project_root)) end

    -- User-defined commands from config
    if config.commands then
        for key, cmd in pairs(config.commands) do
            if type(cmd) == 'string' then
                commands[key] = {
                    name = key,
                    cmd = cmd,
                    cwd = project_root,
                }
            elseif type(cmd) == 'table' then
                if not cmd.name then cmd.name = key end
                if not cmd.cwd then cmd.cwd = project_root end
                commands[key] = cmd
            end
        end
    end

    -- Edit config command
    commands.edit_config = {
        name = 'Edit project config',
        fn = function()
            local config_path = project_root .. '/.neodo.lua'
            if vim.fn.filereadable(config_path) ~= 1 then
                local content = generate_default_config(project_types)
                vim.fn.writefile(vim.split(content, '\n'), config_path)
            end
            vim.cmd('edit ' .. config_path)
        end,
    }

    return commands
end

-- Active projects indexed by root path
local projects = {}

--- Generate default config content for given project types
function M.generate_config(project_types) return generate_default_config(project_types) end

--- Create/load a project
function M.load(project_root, project_types)
    ensure_config(project_root, project_types)

    local config_path = project_root .. '/.neodo.lua'

    local config = {}
    if vim.fn.filereadable(config_path) == 1 then config = load_config(config_path) or {} end

    -- Type keys that map 1:1 to config section names
    local configurable_types = { 'cmake', 'platformio', 'rust', 'node', 'makefile' }

    -- Sync detected subdirs into config as `src` (so modules can resolve cwd).
    -- Also force-activate types declared in config even without filesystem detection.
    for _, type_key in ipairs(configurable_types) do
        local detected = project_types[type_key]
        if detected and detected ~= project_root then
            config[type_key] = config[type_key] or {}
            if not config[type_key].src then
                local rel = detected:sub(#project_root + 2)
                if rel ~= '' then config[type_key].src = rel end
            end
        end
        if not detected and config[type_key] and next(config[type_key]) then
            local dir = config[type_key].src and (project_root .. '/' .. config[type_key].src)
                or project_root
            project_types[type_key] = dir
        end
    end

    local commands = build_commands(config, project_root, project_types)

    local project = {
        root = project_root,
        config = config,
        types = project_types,
        commands = commands,
        last_command = nil,
    }

    projects[project_root] = project

    -- Project type on_load hooks
    if project_types.cmake then cmake.on_load(config, project_root) end
    if project_types.platformio then platformio.on_load(config, project_root) end

    return project
end

--- Get project by root path
function M.get(project_root) return projects[project_root] end

--- Get project for current working directory
function M.get_current()
    local cwd = vim.loop.cwd()
    return projects[cwd]
end

--- Get all loaded projects
function M.get_all() return projects end

--- Reload a project (after config change)
function M.reload(project_root)
    local project = projects[project_root]
    if not project then return end
    return M.load(project_root, project.types)
end

--- Run a command by key
function M.run(project, command_key)
    if not project then
        notify.warning('No project loaded')
        return
    end

    local command = project.commands[command_key]
    if not command then
        notify.warning('Unknown command: ' .. command_key)
        return
    end

    if runner.run(command) then project.last_command = command_key end
end

--- Run last command
function M.run_last(project)
    if not project then
        notify.warning('No project loaded')
        return
    end
    if not project.last_command then
        notify.warning('No last command')
        return
    end
    M.run(project, project.last_command)
end

--- Show command picker
function M.pick_command(project)
    if not project then
        notify.warning('No project loaded')
        return
    end

    local items = {}

    -- Run last command as first item
    if project.last_command and project.commands[project.last_command] then
        local cmd = project.commands[project.last_command]
        table.insert(items, {
            key = project.last_command,
            name = '>> ' .. (cmd.name or project.last_command) .. ' (last)',
        })
    end

    local sorted = {}
    for key, cmd in pairs(project.commands) do
        table.insert(sorted, { key = key, name = cmd.name or key })
    end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    vim.list_extend(items, sorted)

    if #items == 0 then
        notify.warning('No commands available')
        return
    end

    vim.ui.select(items, {
        prompt = 'Neodo',
        format_item = function(item) return item.name end,
        kind = 'neodo.select',
    }, function(selection)
        if not selection then return end
        M.run(project, selection.key)
    end)
end

return M
