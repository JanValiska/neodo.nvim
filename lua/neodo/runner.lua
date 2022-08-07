local M = {}

local global_settings = require("neodo.settings")
local notify = require("neodo.notify")
local log = require("neodo.log")
local projects = require("neodo.projects")
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
                command.on_success(projects[command_context.project_hash])
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

local function get_cmd_string(command, project)
    if type(command.cmd) == "function" then
        local params = {}
        if command.params and type(command.params) == "function" then
            params = command.params()
        else
            params = command.params
        end
        local result = command.cmd(params, project)
        if result ~= nil then
            return result
        end
    else
        return vim.fn.expandcmd(command.cmd)
    end
    return nil
end

local function start_function_command(command, project)
    local params = {}
    if command.params and type(command.params) == "function" then
        params = command.params()
    else
        params = command.params
    end
    if should_notify(command) then
        notify.info("INVOKING", command.name)
    end
    local fuuid = uuid_generator()
    command_contexts[fuuid] = {
        started_at = os.time(),
        command = command,
        project_hash = project.hash,
    }
    vim.schedule(function()
        command.fn(params, project)
        if should_notify(command) then
            notify.info("DONE", command.name)
        end
        if command.on_success and type(command.on_success) == "function" then
            command.on_success(project)
        end
        command_contexts[fuuid] = nil
    end)
end

local function start_cmd(command, project)
    local cmd = get_cmd_string(command, project)
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
        project_hash = project.hash,
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

local function command_enabled(command, project)
    if command.enabled and type(command.enabled) == "function" then
        return command.enabled(command.params, project)
    end
    return true
end

local function command_still_running(command)
    for _, running_command in pairs(command_contexts) do
        if running_command.command == command then
            return true
        end
    end
    return false
end

local function run_project_command(command, project)
    if command == nil then
        log.warning("Command not found")
        return false
    end

    if not command_enabled(command, project) then
        log.warning("Command disabled")
        return false
    end

    if command_still_running(command) then
        log.warning("Command already started")
        return false
    end

    vim.api.nvim_command("cclose")

    if command.fn then
        start_function_command(command, project)
    elseif command.cmd then
        start_cmd(command, project)
    else
        log.error("No 'fn' or 'cmd' defined in given command")
    end

    return true
end

function M.run(command_key)
    if vim.b.neodo_project_hash == nil then
        log.warning("Buffer not attached to any project")
        return
    end

    local project = projects[vim.b.neodo_project_hash]
    local command = project.commands[command_key]
    if run_project_command(command, project) then
        project.last_command = command_key
    end
end

function M.run_last()
    local hash = vim.b.neodo_project_hash
    if hash == nil then
        log.warning("Buffer not attached to any project")
        return
    end

    local project = projects[vim.b.neodo_project_hash]
    if not project.last_command then
        log.warning("No last command defined")
        return
    end
    local command = project.commands[project.last_command]
    run_project_command(command, project)
end

function M.get_enabled_commands_keys(project)
    if project == nil or project.commands == nil then
        return {}
    end

    local keys = {}
    for key, command in pairs(project.commands) do
        if command_enabled(command, project) then
            table.insert(keys, key)
        end
    end
    return keys
end

function M.get_jobs_count()
    return vim.tbl_count(command_contexts)
end

function M.get_jobs()
    return command_contexts
end

return M
