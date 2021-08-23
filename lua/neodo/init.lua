local M = {}

local configuration = require 'neodo.configuration'
local global_settings = require 'neodo.settings'
local root = require 'neodo.root'
local neodo = require 'neodo.do'
local log = require 'neodo.log'

-- per project configurations
local projects = {}

-- called when project root is detected
local function on_project_root(p)
    -- p is nil when no root is detected
    if p == nil then return end

    local hash = configuration.project_hash(p.dir)
    vim.b.project_hash = hash

    if projects[hash] == nil then
        if configuration.has_project_in_the_source_config(p.dir) then
            log('Using .neodo config')
            projects[hash] = {
                type = p.type,
                settings_type = 2,
                settings = require(
                    configuration.get_project_in_the_source_config(p.dir)).settings
            }
        elseif configuration.has_project_out_of_source_config(p.dir) then
            log('Using out of source neodo config')
            projects[hash] = {
                type = p.type,
                settings_type = 1,
                settings = require(
                    configuration.get_project_in_the_source_config(p.dir)).settings
            }
        else
            log('Using global config')
            projects[hash] = {type = p.type, settings_type = 0}
        end
    end

    if projects[hash].settings_type == 0 then
        local settings = global_settings.project_type[p.type]
        if settings.on_attach ~= nil then settings.on_attach() end
    end
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
    local command
    if project.settings_type == 0 then
        local type = project.type
        command = global_settings.project_type[type].commands[command_key]
    else
        command = project.settings.commands[command_key]
    end
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
        if project.settings_type == 0 then
            return vim.tbl_keys(global_settings.project_type[project.type]
                                    .commands)
        else
            return vim.tbl_keys(project.commands)
        end
    end
    return {}
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
    ]],false)

    vim.api.nvim_exec([[
        function! Neodo(command_key)
            :call luaeval("require'neodo'.run(_A)", a:command_key)
        endfunction
    ]],false)

    vim.api.nvim_exec([[
    command! -nargs=1 -complete=customlist,NeodoCompletionsHelper Neodo call Neodo("<args>")
    ]], false)
end

return M
