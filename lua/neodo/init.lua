local M = {}

local has_telescope, telescope = pcall(require, "telescope")

local configuration = require("neodo.configuration")
local global_settings = require("neodo.settings")
local root = require("neodo.root")
local log = require("neodo.log")
local notify = require("neodo.notify")

local picker = require("neodo.picker")
local utils = require("neodo.utils")

-- per project configurations
local projects = require("neodo.projects")
local project_factory = require("neodo.project")

local function load_settings(file)
    return dofile(file)
end

local function change_root(dir)
    if global_settings.change_root then
        vim.api.nvim_set_current_dir(dir)
        if global_settings.change_root_notify then
            notify.info(dir, "Working directory changed")
        end
    end
end

local function load_project(path, project_types_keys)
    local hash = configuration.project_hash(path)

    if global_settings.load_project_notify then
        notify.info(path, "Loading project")
    end

    -- Check if config file and datapath exists
    local config_file, data_path = configuration.get_project_config_and_datapath(path)

    -- load project
    local user_project_settings = nil
    if config_file ~= nil then
        user_project_settings = load_settings(config_file) or {}
    end

    local project_types = {}
    for _, project_type_key in ipairs(project_types_keys) do
        project_types[project_type_key] = global_settings.project_types[project_type_key]
    end
    local project = project_factory.new(path, hash, data_path, config_file, project_types, user_project_settings)
    project.on_attach()
    projects[hash] = project
    return project
end

local function reload_project(project)
    local path = project.path()
    local project_type_keys = project.project_types_keys()

    -- TODO check if some project jobs are running and stop them
    projects[project.hash()] = nil
    project = nil

    vim.schedule(function()
        local p = load_project(path, project_type_keys)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            local hash = utils.get_buf_variable(bufnr, "neodo_project_hash")
            if hash == p.hash() then
                p.buffer_on_attach(bufnr)
            end
        end
    end)
end

local function config_changed(config)
    for _, project in pairs(projects) do
        if project.config_file() == config then
            reload_project(project)
        end
    end
end

-- called when project root is detected
local function on_project_folder_and_types_detected(project_folder_and_types, bufnr)
    local path = project_folder_and_types.path
    local project_types_keys = project_folder_and_types.project_types_keys
    -- p.dir is nil when no root is detected
    if path == nil then
        return
    end

    -- change root
    change_root(path)

    local hash = configuration.project_hash(path)
    -- mark current buffer that it belongs to project
    vim.b.neodo_project_hash = hash

    -- return already loaded project
    local project = projects[hash]
    if project == nil then
        project = load_project(path, project_types_keys)
    end

    -- call buffer on attach handlers
    project.buffer_on_attach(bufnr)
end

local function already_loaded()
    return vim.b.neodo_project_hash ~= nil
end

function M.config_file_written()
    local config = vim.fn.expand(vim.fn.expand("%:p"))
    config_changed(config)
end

local function find_project()
    local basepath = vim.fn.expand("%:p:h")

    if basepath == nil then
        return
    end

    -- replace double // separators
    basepath = basepath:gsub("//", "/")

    local bufnr = vim.api.nvim_get_current_buf()
    for _, project in pairs(projects) do
        if string.find(basepath, project.path()) then
            local project_folder_and_types = {
                path = project.path(),
                project_types_keys = project.project_types_keys(),
            }
            on_project_folder_and_types_detected(project_folder_and_types, bufnr)
        end
    end

    root.find_project(basepath, function(project_folder_and_types)
        on_project_folder_and_types_detected(project_folder_and_types, bufnr)
    end)
end

-- called when the buffer is read first time or using :e
function M.buffer_read()
    -- ignore files with no filetype specified
    local ft = vim.bo.filetype
    if ft == "" then
        return
    end

    -- ignore some special filetypes (qf, etc...)
    local filetype_ignore = { "qf" }
    if vim.tbl_contains(filetype_ignore, ft) then
        return
    end

    -- permit only for specified buffer types
    local buftype_permit = { "", "nowrite" }
    if vim.tbl_contains(buftype_permit, vim.bo.buftype) == false then
        return
    end

    if already_loaded() then
        change_root(projects[vim.b.neodo_project_hash].path())
    else
        find_project()
    end
end

-- called when the buffer is entered(on buffer switch, etc)
function M.buffer_enter()
    -- ignore files with no filetype specified
    local ft = vim.bo.filetype
    if ft == "" then
        return
    end

    -- ignore some special filetypes (qf, etc...)
    local filetype_ignore = { "qf" }
    if vim.tbl_contains(filetype_ignore, ft) then
        return
    end

    -- permit only for specified buffer types
    local buftype_permit = { "", "nowrite" }
    if vim.tbl_contains(buftype_permit, vim.bo.buftype) == false then
        return
    end

    if already_loaded() then
        change_root(projects[vim.b.neodo_project_hash].path())
    end
end

function M.get_project(hash)
    return projects[hash]
end

function M.has_config()
    local buf = vim.api.nvim_win_get_buf(0)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = utils.get_buf_variable(buf, "neodo_project_hash")
        if hash ~= nil then
            local project = projects[hash]
            if project == nil then
                return false
            end
            return project.config_file() ~= nil
        end
    end
    return false
end

M.has_project = function()
    local buf = vim.api.nvim_win_get_buf(0)
    if vim.api.nvim_buf_is_loaded(buf) then
        local hash = utils.get_buf_variable(buf, "neodo_project_hash")
        if hash ~= nil then
            return true
        end
    end
    return false
end

-- called by user code to execute command with given key for current buffer
function M.run(command_key)
    if vim.b.neodo_project_hash == nil then
        log.warning("Buffer not attached to any project")
        return
    end
    projects[vim.b.neodo_project_hash].run(command_key)
end

function M.run_last()
    if vim.b.neodo_project_hash == nil then
        log.warning("Buffer not attached to any project")
        return
    end
    projects[vim.b.neodo_project_hash].run_last_command()
end

function M.neodo()
    if vim.b.neodo_project_hash == nil then
        log.warning("Buffer not attached to any project")
        return
    else
        picker.pick_command()
    end
end

function M.handle_vim_command(command_key)
    if command_key == nil or command_key == "" then
        M.neodo()
    else
        M.run(command_key)
    end
end

function M.completions_helper()
    local project_hash = vim.b.neodo_project_hash
    if project_hash ~= nil then
        return projects[project_hash].get_command_keys()
    end
    return {}
end

function M.edit_project_settings()
    local project_hash = vim.b.neodo_project_hash

    if project_hash == nil then
        log.warning("Cannot edit project settings. Current buffer is not part of project.")
        return
    end

    -- if project has config, edit it
    local project = projects[project_hash]
    if project.config_file() then
        vim.api.nvim_exec(":e " .. project.config_file(), false)
    else
        configuration.ensure_config_file_and_data_path(project, function(res)
            if res then
                vim.api.nvim_exec(":e " .. project.config_file(), false)
            else
                log.error("Cannot create config file")
            end
        end)
    end
end

function M.info()
    require("neodo.info").show()
end

local function register_built_in_project_types()
    require("neodo.project_type.git").register()
    require("neodo.project_type.mongoose").register()
    require("neodo.project_type.cmake").register()
    require("neodo.project_type.php_composer").register()
end

local function register_telescope_extension()
    if not has_telescope then
        return
    end
    telescope.load_extension("neodo")
end

function M.setup(config)
    register_built_in_project_types()
    register_telescope_extension()

    if config then
        global_settings = vim.tbl_deep_extend("force", global_settings, config)
    end

    vim.api.nvim_exec(
        [[
     augroup NeodoBaseAutocmds
       autocmd BufRead * lua require'neodo'.buffer_read()
       autocmd BufEnter * lua require'neodo'.buffer_enter()
       autocmd BufWrite */neodo/*/config.lua lua require'neodo'.config_file_written()
       autocmd BufWrite */.neodo/config.lua lua require'neodo'.config_file_written()
     augroup end
    ]]   ,
        false
    )

    vim.api.nvim_exec(
        [[
     augroup qf
        autocmd!
        autocmd FileType qf set nobuflisted
     augroup end
    ]]   ,
        false
    )

    vim.api.nvim_exec(
        [[
        function! NeodoCompletionsHelper(ArgLead, CmdLine, CursorPos)
            return luaeval("require('neodo').completions_helper()")
        endfunction
    ]]   ,
        false
    )

    vim.api.nvim_exec(
        [[
        function! Neodo(command_key)
            :call luaeval("require'neodo'.handle_vim_command(_A)", a:command_key)
        endfunction
    ]]   ,
        false
    )

    vim.api.nvim_exec(
        [[
    command! -nargs=? -complete=customlist,NeodoCompletionsHelper Neodo call Neodo("<args>")
    ]]   ,
        false
    )

    vim.api.nvim_exec(
        [[
    command! NeodoEditProjectSettings call luaeval("require'neodo'.edit_project_settings()")
    ]]   ,
        false
    )

    vim.api.nvim_exec(
        [[
    command! NeodoInfo call luaeval("require'neodo'.info()")
    ]]   ,
        false
    )
end

return M
