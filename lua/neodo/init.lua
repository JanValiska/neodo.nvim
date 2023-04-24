local M = {}

local configuration = require('neodo.configuration')
local global_settings = require('neodo.settings')
local root = require('neodo.root')
local notify = require('neodo.notify')

local picker = require('neodo.picker')
local utils = require('neodo.utils')
local log = require('neodo.log')

-- per project configurations
local projects = require('neodo.projects')
local Project = require('neodo.project')

local Path = require('plenary.path')

local function set_project_hash(hash, bufnr)
    bufnr = bufnr or vim.api.nvim_win_get_buf(0)
    log.debug('Setting hash', hash, 'for buffer', bufnr)
    return utils.set_buf_variable(bufnr, 'neodo_project_hash', hash)
end

local function get_project_hash(bufnr)
    bufnr = bufnr or vim.api.nvim_win_get_buf(0)
    log.debug('Getting hash of', bufnr)
    return utils.get_buf_variable(bufnr, 'neodo_project_hash')
end

local function change_root(dir)
    if global_settings.change_root then
        log.info('Changing root to:', dir)
        vim.api.nvim_set_current_dir(dir)
        if global_settings.change_root_notify then notify.info(dir, 'Working directory changed') end
    end
end

local function load_project(project_root, project_types)
    if global_settings.load_project_notify then notify.info(project_root, 'Loading project') end
    local project = Project:new(global_settings, project_root, project_types)
    project:call_on_attach()
    projects[project:get_hash()] = project
    log.debug('Loaded project:', vim.inspect(project))
    return project
end

local function reload_project(project)
    local project_path = project:get_path()
    local project_types_paths = project:get_project_types_paths()

    -- TODO check if some project jobs are running and stop them
    projects[project:get_hash()] = nil
    project = nil

    vim.schedule(function()
        local p = load_project(project_path, project_types_paths)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            local hash = get_project_hash(bufnr)
            if hash == p:get_hash() then p:call_buffer_on_attach(bufnr) end
        end
    end)
end

local function config_changed(config)
    for _, project in pairs(projects) do
        if project:get_config_file() == config then reload_project(project) end
    end
end

-- called when project root is detected
local function on_project_types_detected(project_types, bufnr)
    log.debug('Root detected:', vim.inspect(project_types), 'for bufnr', bufnr)
    local project_root = nil

    -- shortest project type dir is project root
    for _, tp in pairs(project_types) do
        if project_root == nil then
            project_root = tp
        else
            if string.len(project_root) > string.len(tp) then project_root = tp end
        end
    end
    if project_root == nil then return end

    change_root(project_root)

    local hash = configuration.project_hash(project_root)

    -- mark current buffer that it belongs to project
    set_project_hash(hash, bufnr)

    -- return already loaded project
    local project = projects[hash]
    if project == nil then project = load_project(project_root, project_types) end

    -- call buffer on attach handlers
    project:call_buffer_on_attach(bufnr)
end

function M.config_file_written()
    local config = vim.fn.expand(vim.fn.expand('%:p'))
    config_changed(config)
end

local function find_project(bufnr)
    local s, basepath = pcall(function() return Path:new(vim.api.nvim_buf_get_name(bufnr)) end)
    if not s then return end

    if basepath == nil then return end

    -- if current buffer belongs to already loaded project then just attach buffer
    log.debug('Finding', basepath.filename, 'in already loaded projects')
    for hash, project in pairs(projects) do
        log.debug('Looking if basepath', basepath.filename, 'is in', project:get_path())
        local start, stop = string.find(basepath.filename, project:get_path(), 1, true)
        log.debug('Find results:', vim.inspect(start), vim.inspect(stop))
        if start and stop and start == 1 then
            log.debug('Basepath', basepath.filename, 'is in', project:get_path())
            change_root(project:get_path())
            set_project_hash(hash, bufnr)
            project:call_buffer_on_attach(bufnr)
            return
        end
    end

    log.debug('Finding root')
    -- try to find project root and project types
    root.find_project_types(basepath:parent().filename, function(project_types)
        log.debug('Found project types:', vim.inspect(project_types))
        on_project_types_detected(project_types, bufnr)
    end)
end

local function is_buffer_valid()
    -- ignore files with no filetype specified
    local ft = vim.bo.filetype
    if ft == '' then return false end

    -- ignore some special filetypes (qf, etc...)
    local filetype_ignore = { 'qf' }
    if vim.tbl_contains(filetype_ignore, ft) then return false end

    -- permit only for specified buffer types
    local buftype_permit = { '', 'nowrite' }
    if vim.tbl_contains(buftype_permit, vim.bo.buftype) == false then return false end
    return true
end

-- called when the buffer is read first time or using :e
function M.handle_buffer(bufnr)
    log.debug('Handling buffer:', bufnr)
    if not is_buffer_valid() then
        log.debug('Buffer', bufnr, 'not valid')
        return
    end

    local hash = get_project_hash(bufnr)
    log.debug('Buffer hash is', hash)
    if hash ~= nil then
        log.debug('Buffer', bufnr, 'already loaded')
        change_root(projects[hash]:get_path())
    else
        log.debug('Buffer', bufnr, 'NOT loaded')
        find_project(bufnr)
    end
end

local startup_done = false

function M.handle_startup()
    if startup_done then return end
    log.debug('Handling startup')

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        M.handle_buffer(tonumber(bufnr))
    end

    startup_done = true
end

function M.get_project(bufnr)
    local hash = get_project_hash(bufnr)
    return hash and projects[hash] or nil
end

function M.has_config()
    local project = M.get_project()
    return project and project:get_config_file()
end

function M.run(command_key)
    local cwd = vim.loop.cwd()
    for _, project in pairs(projects) do
        if project:get_path() == cwd then
            project:run(command_key)
            return
        end
    end
    notify.warning('No project associated with current working directory')
end

function M.run_last()
    local cwd = vim.loop.cwd()
    for _, project in pairs(projects) do
        if project:get_path() == cwd then
            project:run_last_command()
            return
        end
    end
    notify.warning('No project associated with current working directory')
end

function M.neodo()
    local cwd = vim.loop.cwd()
    for _, project in pairs(projects) do
        if project:get_path() == cwd then
            picker.pick_command(project)
            return
        end
    end
    notify.warning('No project associated with current working directory')
end

function M.edit_project_settings()
    local project_hash = get_project_hash()

    if project_hash == nil then
        notify.warning('Cannot edit project settings. Current buffer is not part of project.')
        return
    end

    -- if project has config, edit it
    local project = projects[project_hash]
    if project:get_config_file() then
        vim.api.nvim_exec(':e ' .. project:get_config_file(), false)
    else
        project:create_config_file(function(res)
            if res then
                vim.api.nvim_exec(':e ' .. project:get_config_file(), false)
            else
                notify.error('Cannot create config file')
            end
        end)
    end
end

function M.info()
    for k,v in pairs(projects) do
                log.debug(vim.inspect(v.data_path))
        for pk,pv in pairs(v.project_types.cmake.config.profiles) do
                log.debug(vim.inspect(pk))
        end
    end
    require('neodo.info').show(projects)
end

local function handle_vim_command(command_key)
    if command_key == nil or command_key == '' then
        M.neodo()
    else
        M.run(command_key)
    end
end

local function completions_helper(_, _)
    local project_hash = get_project_hash()
    if project_hash ~= nil then return projects[project_hash]:get_commands_keys() end
    return {}
end

local function register_built_in_project_types()
    require('neodo.project_type.git').register()
    require('neodo.project_type.mongoose').register()
    require('neodo.project_type.cmake').register()
    require('neodo.project_type.php_composer').register()
    require('neodo.project_type.makefile').register()
end

local function register_telescope_extension()
    local has_telescope, telescope = pcall(require, 'telescope')
    if not has_telescope then return end
    telescope.load_extension('neodo')
end

function M.setup(config, neodo_host_config)
    local neodo_basic_autocommands_group =
        vim.api.nvim_create_augroup('NeodoBasicAutocommands', { clear = true })

    vim.api.nvim_create_autocmd({ 'BufEnter' }, {
        group = neodo_basic_autocommands_group,
        pattern = '*',
        callback = function()
            local bufnr = tonumber(vim.fn.expand('<abuf>')) or 0
            vim.schedule(function() M.handle_buffer(bufnr) end)
        end,
    })

    vim.api.nvim_create_autocmd({ 'VimEnter' }, {
        group = neodo_basic_autocommands_group,
        pattern = '*',
        callback = function() M.handle_startup() end,
    })

    vim.api.nvim_create_autocmd('BufWrite', {
        group = neodo_basic_autocommands_group,
        pattern = { '*/neodo/*/config.lua', '*/.neodo/config.lua' },
        callback = function() M.config_file_written() end,
    })

    vim.api.nvim_create_user_command(
        'Neodo',
        function(opts) handle_vim_command(opts.fargs[1]) end,
        { nargs = 1, complete = completions_helper }
    )
    vim.api.nvim_create_user_command('NeodoEditProjectSettings', M.edit_project_settings, {})
    vim.api.nvim_create_user_command('NeodoInfo', M.info, {})

    register_built_in_project_types()
    register_telescope_extension()

    if config then global_settings = utils.tbl_deep_extend('force', global_settings, config) end

    if neodo_host_config then
        local host_config_f, err = loadfile(neodo_host_config)
        if not err and host_config_f then
            global_settings = vim.tbl_deep_extend('force', global_settings, host_config_f() or {})
        end
    end

    log.set_log_level(global_settings.log_level)

    M.handle_startup()
end

return M
