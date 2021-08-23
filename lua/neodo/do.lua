local M = {}

-- list of currently running jobs
local system_jobs = {}

local global_settings = require 'neodo.settings'
local utils = require 'neodo.utils'

-- key/value store for lines produced by currently running jobs
local system_jobs_lines = {}

local notify = require 'notify'
-- local notification = require("neogit.lib.notification")
local notification_timeout = 2500

local latest_buf_id = nil

local latest_win_id = nil

local function notify_info(text, header)
    -- notification.create("TEST")
    notify(text, nil, {title = header, timeout = notification_timeout})
end
-- local function notify_warning(text, header) notify(text, 'warning', {title = header, timeout = notification_timeout}) end
local function notify_error(text, header)
    notify(text, 'error', {title = header, timeout = notification_timeout})
end

local function on_command_success(command, return_code)
    local text = command.name .. ' SUCCESS(' .. return_code .. ')'
    notify_info('OK', text)
    if not command.run_as_background_job and
        global_settings.terminal_close_on_success then
        utils.close_win(latest_win_id)
    end
    if global_settings.qf_close_on_success then
        vim.api.nvim_command("cclose")
    end
end

local function on_command_failed(command, return_code)
    local text = command.name .. ' FAILED(' .. return_code .. ')'
    notify_error('NOK', text)
    if global_settings.qf_open_on_error then vim.api.nvim_command("copen") end
end

local function on_event(job_id, data, event)
    if event == "stdout" or event == "stderr" then
        if data then vim.list_extend(system_jobs_lines[job_id], data) end
    end

    if event == "exit" then
        local command = system_jobs[job_id]
        vim.fn.setqflist({}, ' ', {
            title = command.cmd,
            efm = command.errorformat,
            lines = system_jobs_lines[job_id]
        })
        vim.api.nvim_command("doautocmd QuickFixCmdPost")

        if data == 0 then
            on_command_success(command, data)
        else
            on_command_failed(command, data)
        end
        if global_settings.qf_open_on_stop then
            vim.api.nvim_command("copen")
        end

        system_jobs_lines[job_id] = nil
        system_jobs[job_id] = nil
    end
end

local function start_function(command)
    command.cmd()
    notify_info("", command.name .. ' EXECUTED')
end

local function start_system_command(command)
    local expanded_cmd = vim.fn.expandcmd(command.cmd)

    local job_id = vim.fn.jobstart(expanded_cmd, {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
        stdout_buffered = false,
        stderr_buffered = false
    })

    system_jobs[job_id] = command
    system_jobs_lines[job_id] = {}
    local text = command.name .. ' STARTED'
    notify_info(expanded_cmd, text)
    if global_settings.qf_open_on_start then vim.api.nvim_command("copen") end
end

local function start_terminal_command(command)

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

    -- when the buffer is closed, set the latest buf id to nil else there are
    -- some edge cases with the id being sit but a buffer not being open
    local function onDetach(_, _)
        latest_buf_id = nil
        latest_win_id = nil
    end
    vim.api.nvim_buf_attach(latest_buf_id, false, {on_detach = onDetach})

    -- run the command
    local expanded_cmd = vim.fn.expandcmd(command.cmd)
    local job_id = vim.fn.termopen(expanded_cmd, {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
        stdout_buffered = false,
        stderr_buffered = false
    })

    vim.cmd('keepalt file ' .. 'NeoDo: ' .. expanded_cmd)

    system_jobs[job_id] = command
    system_jobs_lines[job_id] = {}

    local text = command.name .. ' STARTED IN TERMINAL'
    notify_info(expanded_cmd, text)
end

function M.command(command)
    if global_settings.qf_close_on_start then vim.api.nvim_command("cclose") end
    if type(command.cmd) == 'function' then
        start_function(command)
    else
        if command.run_as_background_job then
            start_system_command(command)
        else
            start_terminal_command(command)
        end
    end

end

return M
