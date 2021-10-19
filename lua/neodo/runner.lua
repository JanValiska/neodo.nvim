local M = {}

local global_settings = require 'neodo.settings'
local utils = require 'neodo.utils'
local notify = require 'neodo.notify'
local log = require 'neodo.log'
local projects = require 'neodo.projects'

-- list of currently running jobs
local jobs = {}

local function handle_terminal_and_qf(command, job)
    if not command.run_as_background_job and
        global_settings.terminal_close_on_success then
        vim.api.nvim_buf_delete(job.buf_id, {})
    end
    if global_settings.qf_close_on_success then
        vim.api.nvim_command("cclose")
    end
end

local function on_event(job_id, data, event)
    if event == "stdout" or event == "stderr" then
        if data then vim.list_extend(jobs[job_id].output_lines, data) end
    end

    if event == "exit" then
        local command = jobs[job_id].command
        if command.errorformat then
            vim.fn.setqflist({}, ' ', {
                title = command.cmd,
                efm = command.errorformat,
                lines = jobs[job_id].output_lines
            })
            vim.api.nvim_command("doautocmd QuickFixCmdPost")
        end

        if data == 0 then
            local title = 'NeoDo: ' .. command.name
            notify.info('SUCCESS', title)
            handle_terminal_and_qf(command, jobs[job_id]);
            if command.on_success then command.on_success(projects[jobs[job_id].project_hash]) end
        else
            if data == 130 then
                local text = 'NeoDo: ' .. command.name
                notify.warning("Interrupted (SIGINT)", text)
                handle_terminal_and_qf(command, jobs[job_id]);
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

        jobs[job_id] = nil
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

local function should_notify(command)
    if command.notify ~= nil then return command.notify end
    return true
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
    local result = command.cmd(params, project)
    if result == nil then result = {type = 'success'} end
    if result.type == 'success' then
        if should_notify(command) then notify.info('SUCCESS', title) end
        if command.on_success and type(command.on_success) == 'function' then
            command.on_success(project)
        end
        return
    end
    if result.type == "error" then notify.error(result.text, title) end
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

    jobs[job_id] = {
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


    jobs[job_id] = {
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

function M.run(command, project)
    if global_settings.qf_close_on_start then vim.api.nvim_command("cclose") end
    if command.type == 'function' then
        start_function_command(command, project)
    elseif command.type == 'background' then
        start_background_command(command, project)
    else
        start_terminal_command(command, project)
    end
end

return M
