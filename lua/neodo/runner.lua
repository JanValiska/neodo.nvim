local M = {}

local global_settings = require("neodo.settings")
local notify = require("neodo.notify")
local log = require("neodo.log")
local uuid_generator = require("neodo.uuid")
local os = require("os")

-- list of currently running jobs
local command_contexts = {}

local function find_command_by_job_id(job_id)
    for uuid, command_context in pairs(command_contexts) do
        if command_context.job_id == job_id then
            return uuid, command_context
        end
    end
end

local function should_notify(command)
    if command.notify ~= nil then
        return command.notify
    end
    return true
end

local function close_terminal_on_success(command, job)
    if command.cmd and not command.background and
        global_settings.terminal_close_on_success and not command.keep_terminal_open then
        vim.api.nvim_buf_delete(job.buf_id, {})
    end
end

local function close_terminal_on_fail(command, job)
    if command.cmd and not command.background and command.errorformat and global_settings.terminal_close_on_error then
        vim.api.nvim_buf_delete(job.buf_id, {})
    end
end

local function on_event(job_id, data, event)
    local uuid, command_context = find_command_by_job_id(job_id)

    if event == "stdout" or event == "stderr" then
        if data then
            for _, line in ipairs(data) do
                -- strip dos line endings
                line = line:gsub("\r", "")
                -- strip ANSI color codes
                line = line:gsub("\27%[[0-9;mK]+", "")
                command_context.output_lines[#command_context.output_lines + 1] = line
            end
        end
        return
    end

    if event == "exit" then
        local command = command_context.command

        if data == 0 then
            if should_notify(command) then
                notify.info("SUCCESS", command.name)
            end
            close_terminal_on_success(command, command_context)
            if command.on_success then
                command.on_success({ project = command_context.project, project_type = command_context.project_type })
            end
        else
            if data == 130 then
                notify.warning("Interrupted (SIGINT)", command.name)
                close_terminal_on_success(command, command_context)
            else
                notify.error("FAILED with: " .. data, command.name)

                close_terminal_on_fail(command, command_context)
                if command.errorformat then
                    vim.fn.setqflist({}, " ", {
                        title = command.cmd,
                        efm = command.errorformat or '%m',
                        lines = command_context.output_lines,
                    })
                    vim.api.nvim_command("copen")
                    vim.cmd('wincmd p')
                end
            end
        end

        command_contexts[uuid] = nil
    end
end

local function start_function_command(command, project, project_type)
    local ctx = { params = nil, project = project, project_type = project_type }
    if command.params and type(command.params) == "function" then
        ctx.params = command.params(ctx)
    else
        ctx.params = command.params
    end
    if should_notify(command) then
        notify.info("INVOKING", command.name)
    end
    local fuuid = uuid_generator()
    command_contexts[fuuid] = {
        started_at = os.time(),
        command = command,
        project = project,
        project_type = project_type
    }
    vim.schedule(function()
        command.fn(ctx)
        if should_notify(command) then
            notify.info("DONE", command.name)
        end
        if command.on_success and type(command.on_success) == "function" then
            ctx.params = nil
            command.on_success(ctx)
        end
        command_contexts[fuuid] = nil
    end)
end

local function get_cmd_string(command, project, project_type)
    if type(command.cmd) == "function" then
        local ctx = { params = nil, project = project, project_type = project_type }
        if command.params and type(command.params) == "function" then
            ctx.params = command.params(ctx)
        else
            ctx.params = command.params
        end
        local result = command.cmd(ctx)
        if result ~= nil then
            return result
        end
    elseif type(command.cmd) == "string" then
        return vim.fn.expandcmd(command.cmd)
    end
    return nil
end

local function start_cmd(command, project, project_type)
    local cmd = get_cmd_string(command, project, project_type)
    if cmd == nil then
        log.error("Cannot run command, cmd incorrect")
        return false
    end

    local opts = {
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
        stdout_buffered = false,
        stderr_buffered = false,
    }

    local command_context = {
        started_at = os.time(),
        command = command,
        project = project,
        project_type = project_type,
        output_lines = {},
    }

    local executor = nil
    if command.background then
        executor = function() command_context.job_id = vim.fn.jobstart(cmd, opts) end
    else
        executor = function()
            vim.api.nvim_command("bot 15new")
            command_context.job_id = vim.fn.termopen(cmd, opts)
            vim.wo.number = false
            vim.wo.relativenumber = false
            command_context.buf_id = vim.fn.bufnr()
            vim.api.nvim_buf_set_option(command_context.buf_id, "buflisted", false)
            vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
                buffer = command_context.buf_id,
                callback = function()
                    vim.api.nvim_command("starti")
                end
            })
            vim.schedule(function()
                vim.api.nvim_command("starti")
            end)
        end
    end

    executor()

    command_contexts[uuid_generator()] = command_context

    if should_notify(command) then
        notify.info(cmd, command.name)
    end
end

local function command_still_running(command)
    for _, running_command in pairs(command_contexts) do
        if running_command.command == command then
            return true
        end
    end
    return false
end

function M.run_project_command(command, project, project_type)
    if command_still_running(command) then
        log.warning("Command already started")
        return false
    end

    vim.api.nvim_command("cclose")

    if command.fn then
        start_function_command(command, project, project_type)
        return true
    elseif command.cmd then
        start_cmd(command, project, project_type)
        return true
    end

    log.error("No 'fn' or 'cmd' defined in given command")
    return false
end

function M.get_jobs_count()
    return vim.tbl_count(command_contexts)
end

function M.get_jobs()
    return command_contexts
end

return M
