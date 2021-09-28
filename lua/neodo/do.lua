local M = {}

local global_settings = require 'neodo.settings'
local utils = require 'neodo.utils'
local notify = require 'neodo.notify'
local log = require 'neodo.log'
local projects = require 'neodo.projects'

-- list of currently running jobs
local system_jobs = {}

-- key/value store for lines produced by currently running jobs
local system_jobs_lines = {}

local latest_buf_id = nil

local latest_win_id = nil

local function on_command_success(command, project)
    local title = 'NeoDo: ' .. command.name
    notify.info('SUCCESS', title)
    if not command.run_as_background_job and
        global_settings.terminal_close_on_success then
        utils.close_win(latest_win_id)
    end
    if global_settings.qf_close_on_success then
        vim.api.nvim_command("cclose")
    end

    if command.on_success then command.on_success(project) end
end

local function on_command_failed(command, return_code)
    local title = 'NeoDo: ' .. command.name
    notify.error('FAILED with: ' .. return_code, title)
    if global_settings.qf_open_on_error and command.errorformat then
        vim.api.nvim_command("copen")
    end
end

local function on_command_interrupted(command)
    local text = 'NeoDo: ' .. command.name
    notify.warning("Interrupted (SIGINT)", text)
    if not command.run_as_background_job and
        global_settings.terminal_close_on_success then
        utils.close_win(latest_win_id)
    end
    if global_settings.qf_close_on_success then
        vim.api.nvim_command("cclose")
    end
end

local function on_event(job_id, data, event)
    if event == "stdout" or event == "stderr" then
        if data then vim.list_extend(system_jobs_lines[job_id], data) end
    end

    if event == "exit" then
        local command = system_jobs[job_id].command
        if command.errorformat then
            vim.fn.setqflist({}, ' ', {
                title = command.cmd,
                efm = command.errorformat,
                lines = system_jobs_lines[job_id]
            })
            vim.api.nvim_command("doautocmd QuickFixCmdPost")
        end

        if data == 0 then
            on_command_success(command,
                               projects[system_jobs[job_id].project_hash])
        else
            if data == 130 then
                on_command_interrupted(command)
            else
                on_command_failed(command, data)
            end
            if global_settings.qf_open_on_stop and command.errorformat then
                vim.api.nvim_command("copen")
            end
        end

        system_jobs_lines[job_id] = nil
        system_jobs[job_id] = nil
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

    system_jobs[job_id] = {command = command, project_hash = project.hash}
    system_jobs_lines[job_id] = {}
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

    -- check if a buffer with the latest id is already open, if it is then
    -- delete it and continue
    utils.delete_buf(latest_buf_id)
    utils.close_win(latest_win_id)

    -- create the new buffer
    latest_buf_id = vim.api.nvim_create_buf(false, true)

    -- split the window to create a new buffer and set it to our window
    latest_win_id = utils.aboveleft_split(latest_buf_id)

    -- make the new buffer smaller
    utils.resize(false, "-5")

    -- close the buffer when escape is pressed :)
    vim.api.nvim_buf_set_keymap(latest_buf_id, "n", "<Esc>", ":q<CR>",
                                {noremap = true, silent = true})
    vim.wo.number = false
    vim.wo.relativenumber = false

    -- when the buffer is closed, set the latest buf id to nil else there are
    -- some edge cases with the id being sit but a buffer not being open
    local function onDetach(_, _)
        latest_buf_id = nil
        latest_win_id = nil
    end
    vim.api.nvim_buf_attach(latest_buf_id, false, {on_detach = onDetach})

    local job_id = vim.fn.termopen(cmd, {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
        stdout_buffered = false,
        stderr_buffered = false
    })

    -- vim.cmd('keepalt file ' .. 'NeoDo: ' .. cmd)

    system_jobs[job_id] = {command = command, project_hash = project.hash}
    system_jobs_lines[job_id] = {}

    if should_notify(command) then
        local text = 'NeoDo: ' .. command.name
        notify.info(cmd, text)
    end
end

function M.command(command, project)
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
