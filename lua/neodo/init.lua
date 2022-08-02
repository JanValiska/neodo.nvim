local M = {}

local has_telescope, telescope = pcall(require, "telescope")

local configuration = require("neodo.configuration")
local global_settings = require("neodo.settings")
local root = require("neodo.root")
local log = require("neodo.log")
local notify = require("neodo.notify")

local picker = require("neodo.picker")
local runner = require("neodo.runner")
local utils = require("neodo.utils")

-- per project configurations
local projects = require("neodo.projects")

local function load_settings(file)
    return dofile(file)
end

local function load_and_get_merged_config(project_config_file, global_project_settings)
    local settings = load_settings(project_config_file)
    if settings == nil then
        return global_project_settings
    end
    return vim.tbl_deep_extend("force", global_project_settings, settings)
end

local function change_root(dir)
    if global_settings.change_root then
        vim.api.nvim_set_current_dir(dir)
        if global_settings.change_root_notify then
            notify.info(dir, "Working directory changed")
        end
    end
end

local function call_buffer_on_attach(bufnr, project)
    local project_buffer_on_attach = project.buffer_on_attach
    if project_buffer_on_attach and type(project_buffer_on_attach) == "function" then
        project_buffer_on_attach(bufnr)
    end

    -- call project specific on attach
    local user_buffer_on_attach = project.user_buffer_on_attach
    if user_buffer_on_attach and type(user_buffer_on_attach) == "function" then
        user_buffer_on_attach(bufnr)
    end
end

local function call_on_attach(project)
    local global_on_attach = project.on_attach
    if global_on_attach and type(global_on_attach) == "function" then
        global_on_attach(project)
    end

    -- call project specific on attach
    local user_on_attach = project.user_on_attach
    if user_on_attach and type(user_on_attach) == "function" then
        user_on_attach(project)
    end
end

local function fix_command_names(project)
    for key, command in pairs(project.commands) do
        if not command.name then
            command.name = key
        end
    end
end

local function load_project(path, type)
    local hash = configuration.project_hash(path)

    if global_settings.load_project_notify then
        notify.info(path, "NeoDo: Loading project")
    end

    -- Check if config file and datapath exists
    local config_file, data_path = configuration.get_project_config_and_datapath(path)

    -- load project
    local project = {}
    if config_file ~= nil then
        if type == nil then
            project = load_settings(config_file) or {}
        else
            local global_project_settings = global_settings.project_type[type]
            project = load_and_get_merged_config(config_file, global_project_settings)
        end
    else
        if type ~= nil then
            project = global_settings.project_type[type]
        else
            project = global_settings.generic_project_settings
        end
    end

    fix_command_names(project)

    project.path = path
    project.type = type
    project.hash = hash
    project.data_path = data_path
    project.config_file = config_file
    call_on_attach(project)
    projects[hash] = project
    return projects[hash]
end

local function reload_project(project)
    local dir = project.path
    local type = project.type

    -- TODO check if some project jobs are running and stop them
    projects[project.hash] = nil
    project = nil

    vim.schedule(function()
        local p = load_project(dir, type)
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            local hash = utils.get_buf_variable(buf, "neodo_project_hash")
            if hash == p.hash then
                call_buffer_on_attach(buf, p)
            end
        end
    end)
end

local function config_changed(config)
    for _, project in pairs(projects) do
        if project.config_file and project.config_file == config then
            reload_project(project)
        end
    end
end

-- called when project root is detected
local function on_project_dir_detected(p, bufnr)
    -- p.dir is nil when no root is detected
    if p.path == nil then
        return
    end

    -- change root
    change_root(p.path)

    -- return already loaded project
    local project = projects[configuration.project_hash(p.path)]
    if project == nil then
        project = load_project(p.path, p.type)
    end

    -- mark current buffer that it belongs to project
    vim.b.neodo_project_hash = project.hash

    -- call buffer on attach handlers
    call_buffer_on_attach(bufnr, project)
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
        if string.find(basepath, project.path) then
            local p = {
                path = project.path,
                type = project.type,
            }
            on_project_dir_detected(p, bufnr)
        end
    end

    root.find_project(basepath, function(p)
        on_project_dir_detected(p, bufnr)
    end)
end

-- called when the buffer is entered first time
function M.buffer_entered()
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
        change_root(projects[vim.b.neodo_project_hash].path)
    else
        find_project()
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
            return project.config_file ~= nil
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
    runner.run(command_key)
end

function M.run_last()
    runner.run_last()
end

function M.get_command_params(command_key)
    if vim.b.neodo_project_hash == nil then
        log("Buffer not attached to any project")
        return
    end

    local project = projects[vim.b.neodo_project_hash]
    local command = project.commands[command_key]
    if command == nil then
        log("Unknown command '" .. command_key .. "'")
        return nil
    else
        return command.params
    end
end

function M.neodo()
    if vim.b.neodo_project_hash == nil then
        log("Buffer not attached to any project")
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
        local project = projects[project_hash]
        return runner.get_enabled_commands_keys(project)
    end
    return {}
end

function M.edit_project_settings()
    local project_hash = vim.b.neodo_project_hash

    if project_hash == nil then
        log("Cannot edit project settings. Current buffer is not part of project.")
        return
    end

    -- if project has config, edit it
    local project = projects[project_hash]
    if project.config_file then
        vim.api.nvim_exec(":e " .. project.config_file, false)
    else
        configuration.ensure_config_file_and_data_path(project, function(res)
            if res then
                vim.api.nvim_exec(":e " .. project.config_file, false)
            else
                log("Cannot create config file")
            end
        end)
    end
end

function M.info()
    require("neodo.info").show()
end

local function register_built_in_project_types()
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
     augroup Mongoose
       autocmd BufEnter * lua require'neodo'.buffer_entered()
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
