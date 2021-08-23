local M = {}

local configuration = require 'neodo.configuration'
local global_settings = require 'neodo.settings'
local root = require 'neodo.root'
local neodo = require 'neodo.do'
local log = require 'neodo.log'

-- per project configurations
local projects = {}

local function load_and_get_merged_config(project_specific_config_file,
                                          global_project_config)
    local config = assert(loadfile(project_specific_config_file))()
    if config == nil then
        return global_project_config
    end
    return vim.tbl_deep_extend('force', global_project_config, config)
end

-- called when project root is detected
local function on_project_root(p)
    -- p is nil when no root is detected
    if p == nil then return end

    local hash = configuration.project_hash(p.dir)
    vim.b.project_hash = hash

    -- ensure project dir is created

    local global_project_settings = global_settings.project_type[p.type]

    if projects[hash] == nil then
        if configuration.has_project_in_the_source_config(p.dir) then
            log('Using .neodo config')
            projects[hash] = {
                path = p.dir,
                type = p.type,
                settings_type = 2,
                settings = load_and_get_merged_config(
                    configuration.get_project_in_the_source_config(p.dir),
                    global_project_settings)
            }
        elseif configuration.has_project_out_of_source_config(p.dir) then
            log('Using out of source neodo config')
            projects[hash] = {
                path = p.dir,
                type = p.type,
                settings_type = 1,
                settings = load_and_get_merged_config(
                    configuration.get_project_out_of_source_config(p.dir),
                    global_project_settings)
            }
        else
            log('Using global config')
            projects[hash] = {
                path = p.dir,
                type = p.type,
                settings_type = 0,
                settings = global_project_settings
            }
        end
    end

    -- call also global on attach function if shouldn't be skipped
    if projects[hash].settings.skip_global_on_attach ~= nil and
        projects[hash].settings.skip_global_on_attach == false then
        local on_attach = projects[hash].settings.on_attach
        if on_attach and type(on_attach) == 'function' then on_attach() end
    end

    -- call project specific on attach
    local on_attach = projects[hash].settings.on_attach
    if on_attach and type(on_attach) == 'function' then on_attach() end
end

-- called when the buffer is entered first time
function M.buffer_entered()
    local ft = vim.bo.filetype
    if ft == '' then return end
    local basepath = vim.fn.expand(vim.fn.expand('%:p:h'))
    if basepath == nil then return end
    root.find_project_root_and_type(basepath, on_project_root)
end

-- called by user code to execute command with given key for current buffer
function M.run(command_key)
    if vim.b.project_hash == nil then
        log('Buffer not attached to any project')
        return
    end

    local project = projects[vim.b.project_hash]
    local command = project.settings.commands[command_key]
    if command == nil then
        log('Unknown command \'' .. command_key .. '\'')
    else
        neodo.command(command)
    end
end

function M.completions_helper()
    local project_hash = vim.b.project_hash
    if project_hash ~= nil then
        local project = projects[project_hash]
        return vim.tbl_keys(project.settings.commands)
    end
    return {}
end

function M.edit_project_settings()
    local project_hash = vim.b.project_hash
    if project_hash ~= nil then
        local project = projects[project_hash]
        if project.settings_type == 2 then
            vim.api.nvim_exec(":e " ..
                                  configuration.get_project_in_the_source_config(
                                      project.path), false)
        elseif project.settings_type == 1 then
            vim.api.nvim_exec(":e " ..
                                  configuration.get_project_out_of_source_config(
                                      project.path), false)
        else
            local ans = vim.fn.input(
                            "Project config doesn't exists. Create OutOfSource(o), InTheSource(i), Cancel(c): ")
            if ans == 'o' then
                print("Creating Out of source config")
                configuration.create_out_of_source_config_file(project.path,
                                                               function(path)
                    if path ~= nil then
                        vim.api.nvim_exec(":e " .. path, false)
                    end
                end)
            elseif ans == 'i' then
                print("Creating in the source config")
                configuration.create_in_the_source_config_file(project.path,
                                                               function(path)
                    if path ~= nil then
                        vim.api.nvim_exec(":e " .. path, false)
                    end
                end)
            else
                print("Canceling")
                return
            end

        end
    else
        log(
            "Cannot edit project settings. Current buffer is not part of project.")
    end
end

function M.setup(config)
    if config then
        global_settings = vim.tbl_deep_extend('force', global_settings, config)
    end
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
            :call luaeval("require'neodo'.run(_A)", a:command_key)
        endfunction
    ]], false)

    vim.api.nvim_exec([[
    command! -nargs=1 -complete=customlist,NeodoCompletionsHelper Neodo call Neodo("<args>")
    ]], false)

    vim.api.nvim_exec([[
    command! NeodoEditProjectSettings call luaeval("require'neodo'.edit_project_settings()")
    ]], false)
end

return M
