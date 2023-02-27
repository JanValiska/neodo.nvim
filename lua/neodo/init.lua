local M = {}

local configuration = require('neodo.configuration')
local global_settings = require('neodo.settings')
local root = require('neodo.root')
local notify = require('neodo.notify')

local picker = require('neodo.picker')
local utils = require('neodo.utils')

-- per project configurations
local projects = require('neodo.projects')
local Project = require('neodo.project')

local function change_root(dir)
    if global_settings.change_root then
        vim.api.nvim_set_current_dir(dir)
        if global_settings.change_root_notify then notify.info(dir, 'Working directory changed') end
    end
end

local function load_project(path, project_types_keys)
    if global_settings.load_project_notify then notify.info(path, 'Loading project') end
    local project = Project:new(global_settings, path, project_types_keys)
    project:call_on_attach()
    projects[project:get_hash()] = project
    return project
end

local function reload_project(project)
    local path = project:get_path()
    local project_type_keys = project:get_project_types_keys()

    -- TODO check if some project jobs are running and stop them
    projects[project:get_hash()] = nil
    project = nil

    vim.schedule(function()
        local p = load_project(path, project_type_keys)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            local hash = utils.get_buf_variable(bufnr, 'neodo_project_hash')
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
local function on_project_folder_and_types_detected(project_folder_and_types, bufnr)
    local path = project_folder_and_types.path
    local project_types_keys = project_folder_and_types.project_types_keys

    -- p.dir is nil when no root is detected
    if path == nil then return end

    change_root(path)

    local hash = configuration.project_hash(path)

    -- mark current buffer that it belongs to project
    vim.b.neodo_project_hash = hash

    -- return already loaded project
    local project = projects[hash]
    if project == nil then project = load_project(path, project_types_keys) end

    -- call buffer on attach handlers
    project:call_buffer_on_attach(bufnr)
end

local function already_loaded() return vim.b.neodo_project_hash ~= nil end

function M.config_file_written()
    local config = vim.fn.expand(vim.fn.expand('%:p'))
    config_changed(config)
end

local function find_project()
    local basepath = vim.fn.expand('%:p:h')

    if basepath == nil then return end

    -- replace double // separators
    basepath = basepath:gsub('//', '/')

    -- if current buffer belongs to already loaded project then just attach buffer
    local bufnr = vim.api.nvim_get_current_buf()
    for hash, project in pairs(projects) do
        if string.find(basepath, project:get_path()) then
            change_root(project:get_path())
            vim.b.neodo_project_hash = hash
            project:call_buffer_on_attach(bufnr)
            return
        end
    end

    -- try to find project root and project types
    root.find_project(
        basepath,
        function(project_folder_and_types)
            on_project_folder_and_types_detected(project_folder_and_types, bufnr)
        end
    )
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
function M.buffer_read()
    if not is_buffer_valid() then return end

    if already_loaded() then
        change_root(projects[vim.b.neodo_project_hash]:get_path())
    else
        find_project()
    end
end

-- called when the buffer is entered(on buffer switch, etc)
function M.buffer_enter()
    if not is_buffer_valid() then return end

    if already_loaded() then change_root(projects[vim.b.neodo_project_hash]:get_path()) end
end

function M.get_project()
    local buf = vim.api.nvim_win_get_buf(0)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = utils.get_buf_variable(buf, 'neodo_project_hash')
        if hash ~= nil then return projects[hash] end
    end
    return nil
end

function M.has_config()
    local project = M.get_project()
    return project and project:get_config_file()
end

M.has_project = function()
    local buf = vim.api.nvim_win_get_buf(0)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = utils.get_buf_variable(buf, 'neodo_project_hash')
        if hash ~= nil then return true end
    end
    return false
end

-- called by user code to execute command with given key for current buffer
function M.run(command_key)
    if vim.b.neodo_project_hash == nil then
        notify.warning('Buffer not attached to any project')
        return
    end
    projects[vim.b.neodo_project_hash]:run(command_key)
end

function M.run_last()
    if vim.b.neodo_project_hash == nil then
        notify.warning('Buffer not attached to any project')
        return
    end
    projects[vim.b.neodo_project_hash]:run_last_command()
end

function M.neodo()
    if vim.b.neodo_project_hash == nil then
        notify.warning('Buffer not attached to any project')
        return
    else
        picker.pick_command(projects)
    end
end

function M.edit_project_settings()
    local project_hash = vim.b.neodo_project_hash

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

function M.info() require('neodo.info').show(projects) end

local function handle_vim_command(command_key)
    if command_key == nil or command_key == '' then
        M.neodo()
    else
        M.run(command_key)
    end
end

local function completions_helper(_, _)
    local project_hash = vim.b.neodo_project_hash
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

function M.setup(config)
    register_built_in_project_types()
    register_telescope_extension()

    if config then global_settings = utils.tbl_deep_extend('force', global_settings, config) end

    local neodo_basic_autocommands_group =
        vim.api.nvim_create_augroup('NeodoBasicAutocommands', { clear = true })

    vim.api.nvim_create_autocmd('BufRead', {
        group = neodo_basic_autocommands_group,
        pattern = '*',
        callback = function() M.buffer_read(vim.fn.expand('<abuf>')) end,
    })

    vim.api.nvim_create_autocmd('BufEnter', {
        group = neodo_basic_autocommands_group,
        pattern = '*',
        callback = function() M.buffer_enter(vim.fn.expand('<abuf>')) end,
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
end

return M
