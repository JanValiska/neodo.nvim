local M = {}

local has_telescope, telescope = pcall(require, "telescope")

local configuration = require 'neodo.configuration'
local global_settings = require 'neodo.settings'
local root = require 'neodo.root'
local neodo = require 'neodo.do'
local log = require 'neodo.log'
local notify = require 'neodo.notify'

-- per project configurations
local projects = require 'neodo.projects'

local function load_settings(file)
    local settings = assert(loadfile(file))()
    return settings
end

local function load_and_get_merged_config(project_config_file,
                                          global_project_settings)
    local settings = load_settings(project_config_file)
    if settings == nil then return global_project_settings end
    return vim.tbl_deep_extend('force', global_project_settings, settings)
end

local function change_root(dir)
    if global_settings.change_root then
        vim.api.nvim_set_current_dir(dir)
        if global_settings.change_root_notify then
            notify.info(dir, "Working directory changed")
        end
    end
end

local function call_buffer_on_attach(project)
    local global_on_attach = project.buffer_on_attach
    if global_on_attach and type(global_on_attach) == 'function' then
        global_on_attach()
    end

    -- call project specific on attach
    local user_on_attach = project.user_buffer_on_attach
    if user_on_attach and type(user_on_attach) == 'function' then
        user_on_attach()
    end
end

local function call_on_attach(project)
    local global_on_attach = project.on_attach
    if global_on_attach and type(global_on_attach) == 'function' then
        global_on_attach(project)
    end

    -- call project specific on attach
    local user_on_attach = project.user_on_attach
    if user_on_attach and type(user_on_attach) == 'function' then
        user_on_attach(project)
    end
end

local function load_project(dir, type)
    local hash = configuration.project_hash(dir)

    -- return already loaded project
    if projects[hash] ~= nil then return projects[hash] end

    local config_file = nil
    local data_path = nil

    -- load project
    if configuration.has_project_in_the_source_config(dir) then
        notify.info(dir, "NeoDo: Loading " .. (type or 'generic') ..
                        " project settings(.neodo)")
        config_file = configuration.get_project_in_the_source_config(dir)
        data_path = configuration.get_project_in_source_data_path(dir)
    elseif configuration.has_project_out_of_source_config(dir) then
        notify.info(dir, "NeoDo: Loading " .. (type or 'generic') ..
                        " project settings(out of source)")
        config_file = configuration.get_project_out_of_source_config(dir)
        data_path = configuration.get_project_data_path(dir)
    else
        notify.info(dir, "NeoDo: Loading " .. (type or 'generic') ..
                        " project settings(global)")
    end

    local project = {}
    if config_file ~= nil then
        if type == nil then
            project = load_settings(config_file) or {}
        else
            local global_project_settings = global_settings.project_type[type]
            project = load_and_get_merged_config(config_file,
                                                  global_project_settings)
        end
    else
        if type ~= nil then
            project = global_settings.project_type[type]
        else
            project = global_settings.generic_project_settings
        end
    end

    project.path = dir
    project.type = type
    project.hash = hash
    project.data_path = data_path
    project.config_file = config_file

    projects[hash] = project

    call_on_attach(project)

    return project
end

-- called when project root is detected
local function on_project_dir_detected(p)
    -- p.dir is nil when no root is detected
    if p.dir == nil then return end

    -- change root
    change_root(p.dir)

    local project = load_project(p.dir, p.type)

    -- mark current buffer that it belongs to project
    vim.b.neodo_project_hash = project.hash

    -- call buffer on attach handlers
    call_buffer_on_attach(project)
end

local filetype_ignore = {'qf'}

local buftype_permit = {'', 'nowrite'}

local function already_loaded() return vim.b.neodo_project_hash ~= nil end

local function command_enabled(command, project)
    if command.enabled and type(command.enabled) == 'function' then
        return command.enabled(command.params, project)
    end
    return true
end

-- called when the buffer is entered first time
function M.buffer_entered()
    if already_loaded() then change_root(projects[vim.b.neodo_project_hash].path) end
end

function M.buffer_new_or_read()
    local ft = vim.bo.filetype

    -- if buffer is assigned to project already, just change root if needed
    if already_loaded() then
        change_root(projects[vim.b.neodo_project_hash].path)
        return
    end

    if ft == '' then return end

    if vim.tbl_contains(filetype_ignore, ft) then return end

    if vim.tbl_contains(buftype_permit, vim.bo.buftype) == false then return end

    local basepath = vim.fn.expand(vim.fn.expand('%:p:h'))
    if basepath == nil then return end

    root.find_project(basepath, on_project_dir_detected)
end

function M.get_project(hash) return projects[hash] end

-- called by user code to execute command with given key for current buffer
function M.run(command_key)
    if vim.b.neodo_project_hash == nil then
        log('Buffer not attached to any project')
        return
    end

    local project = projects[vim.b.neodo_project_hash]
    local command = project.commands[command_key]
    if command == nil then
        log('Unknown command \'' .. command_key .. '\'')
    else
        if command_enabled(command, project) then
            neodo.command(command, project)
        end
    end
end

function M.get_command_params(command_key)
    if vim.b.neodo_project_hash == nil then
        log('Buffer not attached to any project')
        return
    end

    local project = projects[vim.b.neodo_project_hash]
    local command = project.commands[command_key]
    if command == nil then
        log('Unknown command \'' .. command_key .. '\'')
        return nil
    else
        return command.params
    end
end

function M.neodo()
    if vim.b.neodo_project_hash == nil then
        log('Buffer not attached to any project')
        return
    else
        if has_telescope then
            telescope.extensions.neodo.neodo()
        else
            log("Provide command")
        end
    end
end

function M.handle_vim_command(command_key)
    if command_key == nil or command_key == '' then
        M.neodo()
    else
        M.run(command_key)
    end
end

function M.get_enabled_commands_keys(project)
    local keys = {}
    for key, command in pairs(project.commands) do
        if command_enabled(command, project) then table.insert(keys, key) end
    end
    return keys
end

function M.completions_helper()
    local project_hash = vim.b.neodo_project_hash
    if project_hash ~= nil then
        local project = projects[project_hash]
        return vim.tbl_keys(M.get_enabled_commands_keys(project))
    end
    return {}
end

function M.edit_project_settings()
    local project_hash = vim.b.neodo_project_hash
    if project_hash ~= nil then
        local project = projects[project_hash]
        if project.config_file then
            vim.api.nvim_exec(":e " .. project.config_file, false)
        else
            local ans = vim.fn.input(
                            "Create project config out of source(o), in the source(i), cancel(c): ")
            if ans == 'o' then
                configuration.create_out_of_source_config_file(project.path,
                                                               function(path)
                    if path then
                        vim.api.nvim_exec(":e " .. path, false)
                        project.config_file = path
                    end
                end)
            elseif ans == 'i' then
                configuration.create_in_the_source_config_file(project.path,
                                                               function(path)
                    if path then
                        vim.api.nvim_exec(":e " .. path, false)
                        project.config_file = path
                    end
                end)
            else
                log("Canceling")
                return
            end

        end
    else
        log(
            "Cannot edit project settings. Current buffer is not part of project.")
    end
end

local function register_built_in_project_types()
    require'neodo.project_type.mongoose'.register()
    require'neodo.project_type.cmake'.register()
end

local function register_telescope_extension()
    if not has_telescope then return end
    telescope.load_extension('neodo')
end

function M.setup(config)
    register_built_in_project_types()
    register_telescope_extension()

    if config then
        global_settings = vim.tbl_deep_extend('force', global_settings, config)
    end

    vim.api.nvim_exec([[
     augroup Mongoose
       autocmd BufNewFile,BufRead * lua require'neodo'.buffer_new_or_read()
     augroup end
    ]], false)

    vim.api.nvim_exec([[
     augroup Mongoose
       autocmd BufEnter * lua require'neodo'.buffer_entered()
     augroup end
    ]], false)

    vim.api.nvim_exec([[
     augroup qf
        autocmd!
        autocmd FileType qf set nobuflisted
     augroup end
    ]], false)

    vim.api.nvim_exec([[
        function! NeodoCompletionsHelper(ArgLead, CmdLine, CursorPos)
            return luaeval("require('neodo').completions_helper()")
        endfunction
    ]], false)

    vim.api.nvim_exec([[
        function! Neodo(command_key)
            :call luaeval("require'neodo'.handle_vim_command(_A)", a:command_key)
        endfunction
    ]], false)

    vim.api.nvim_exec([[
    command! -nargs=? -complete=customlist,NeodoCompletionsHelper Neodo call Neodo("<args>")
    ]], false)

    vim.api.nvim_exec([[
    command! NeodoEditProjectSettings call luaeval("require'neodo'.edit_project_settings()")
    ]], false)
end

return M
