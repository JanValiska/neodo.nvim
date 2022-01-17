local M = {}

local global_settings = require 'neodo.settings'
local utils = require 'neodo.utils'
local notify = require 'neodo.notify'
local log = require 'neodo.log'
local projects = require 'neodo.projects'
local uuid = require'neodo.uuid'
local os = require'os'

-- list of currently running jobs
local commands = {}

local function find_command_by_job_id(job_id)
    for uuid, command in pairs(commands) do
        if command.job_id == job_id then
            return uuid,command
        end
    end
end

local function should_notify(command)
    if command.notify ~= nil then return command.notify end
    return true
end

local function handle_terminal_and_qf(command, job)
    if not command.type or command.type == 'terminal' and
        global_settings.terminal_close_on_success then
        vim.api.nvim_buf_delete(job.buf_id, {})
    end
    if global_settings.qf_close_on_success then
        vim.api.nvim_command("cclose")
    end
end

local function on_event(job_id, data, event)
    local cuuid, running_command = find_command_by_job_id(job_id)

    if event == "stdout" or event == "stderr" then
        if data then vim.list_extend(running_command.output_lines, data) end
        return
    end

    if event == "exit" then
        local command = running_command.command
        if command.errorformat then
            vim.fn.setqflist({}, ' ', {
                title = command.cmd,
                efm = command.errorformat,
                lines = running_command.output_lines
            })
            vim.api.nvim_command("doautocmd QuickFixCmdPost")
        end

        if data == 0 then
            local title = 'NeoDo: ' .. command.name
            if should_notify(command) then
            notify.info('SUCCESS', title)
            end
            handle_terminal_and_qf(command, running_command);
            if command.on_success then command.on_success(projects[running_command.project_hash]) end
        else
            if data == 130 then
                local text = 'NeoDo: ' .. command.name
                notify.warning("Interrupted (SIGINT)", text)
                handle_terminal_and_qf(command, running_command);
            else
                local title = 'NeoDo: ' .. command.name
                notify.error('FAILED with: ' .. data, title)
                if global_settings.qf_open_on_error and command.errorformat then
                    vim.api.nvim_command("copen")
                end
            end
            if global_settings.qf_open_on_stop and command.errorformat then
                vim.api.nvim_command("copen")
            end
        end

        commands[cuuid] = nil
    end
end

local function get_cmd_string(command, project)
    local cmd = nil
    if (type(command.cmd) == 'function') then
        local params = {}
        if command.params and type(command.params) == "function" then
            params = command.params()
        else
            params = command.params
        end
        local result = command.cmd(params, project)
        if result.type == 'success' then cmd = result.text end
        if result.type == 'error' then
            notify.error(result.text, 'Neodo: ' .. command.name)
            return nil
        end
    else
        cmd = vim.fn.expandcmd(command.cmd)
    end
    return cmd
end

local function start_function_command(command, project)
    local params = {}
    if command.params and type(command.params) == "function" then
        params = command.params()
    else
        params = command.params
    end
    local title = 'NeoDo: ' .. command.name
    if should_notify(command) then notify.info("Invoking", title) end
    local fuuid = uuid()
    commands[fuuid] = {
        started_at = os.time(),
        command = command,
        project_hash = project.hash
    }
    vim.schedule(function()
        local result = command.cmd(params, project)
        if result == nil then result = {type = 'success'} end
        if result.type == 'success' then
            if should_notify(command) then notify.info('SUCCESS', title) end
            if command.on_success and type(command.on_success) == 'function' then
                command.on_success(project)
            end
        end
        if result.type == "error" then notify.error(result.text, title) end
        commands[fuuid] = nil
    end)
end

local function start_background_command(command, project)
    local cmd = get_cmd_string(command, project)
    local job_id = vim.fn.jobstart(cmd, {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
        stdout_buffered = false,
        stderr_buffered = false
    })

    commands[uuid()] = {
        job_id = job_id,
        started_at = os.time(),
        command = command,
        project_hash = project.hash,
        buf_id = nil,
        win_id = nil,
        output_lines = {}
    }
    if should_notify(command) then
        local text = 'NeoDo: ' .. command.name
        notify.info(cmd, text)
    end
    if global_settings.qf_open_on_start then vim.api.nvim_command("copen") end
end

local function start_terminal_command(command, project)

    -- run the command
    local cmd = get_cmd_string(command, project)
    if cmd == nil then
        log("Cannot create command")
        return
    end

    -- create the new buffer
    vim.api.nvim_command("bot 15new")
    local job_id = vim.fn.termopen(cmd, {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
        stdout_buffered = false,
        stderr_buffered = false
    })
    vim.wo.number = false
    vim.wo.relativenumber = false
    local buf_id = vim.fn.bufnr()
    vim.api.nvim_buf_set_option(buf_id, 'buflisted', false)
    -- vim.api.nvim_command("autocmd! BufWinEnter,WinEnter term://* startinsert")


    commands[uuid()] = {
        job_id = job_id,
        started_at = os.time(),
        command = command,
        project_hash = project.hash,
        buf_id = buf_id,
        output_lines = {}
    }

    if should_notify(command) then
        local text = 'NeoDo: ' .. command.name
        notify.info(cmd, text)
    end
    vim.schedule(function()
        vim.api.nvim_command("starti")
    end)
end

local function command_enabled(command, project)
    if command.enabled and type(command.enabled) == 'function' then
        return command.enabled(command.params, project)
    end
    return true
end

local function run_project_command(command, project)
    if global_settings.qf_close_on_start then vim.api.nvim_command("cclose") end
    if command.type == 'function' then
        start_function_command(command, project)
    elseif command.type == 'background' then
        start_background_command(command, project)
    else
        start_terminal_command(command, project)
    end
end

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
            run_project_command(command, project)
        end
    end
end

function M.get_enabled_commands_keys(project)
    if project == nil or project.commands == nil then
        return {}
    end

    local keys = {}
    for key, command in pairs(project.commands) do
        if command_enabled(command, project) then table.insert(keys, key) end
    end
    return keys
end

function M.get_jobs_count()
    return vim.tbl_count(commands)
end

function M.get_jobs()
    return commands
end

return M
