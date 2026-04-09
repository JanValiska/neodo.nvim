local M = {}

local notify = require('neodo.notify')

local jobs = {}
local job_counter = 0

local function strip_line(line)
    line = line:gsub('\r', '')
    line = line:gsub('\27%[[0-9;mK]+', '')
    return line
end

local function on_event(job_id, data, event)
    local job
    for _, j in pairs(jobs) do
        if j.job_id == job_id then
            job = j
            break
        end
    end
    if not job then return end

    if event == 'stdout' or event == 'stderr' then
        if data then
            for _, line in ipairs(data) do
                job.output[#job.output + 1] = strip_line(line)
            end
        end
        return
    end

    if event == 'exit' then
        job.running = false
        if data == 0 then
            if job.command.notify then
                notify.info('SUCCESS', job.command.name)
            end
            if job.command.on_success then
                job.command.on_success()
            end
        elseif data == 130 then
            notify.warning('Interrupted', job.command.name)
        else
            notify.error('FAILED with: ' .. data, job.command.name)
        end

        if job.command.errorformat then
            vim.fn.setqflist({}, ' ', {
                title = job.command.name,
                efm = job.command.errorformat,
                lines = job.output,
            })
        end
    end
end

function M.run(command)
    if not command then return false end

    if command.fn then
        if command.notify then notify.info('INVOKING', command.name) end
        vim.schedule(function()
            command.fn()
            if command.notify then notify.info('DONE', command.name) end
            if command.on_success then command.on_success() end
        end)
        return true
    end

    if not command.cmd then
        notify.error("No 'fn' or 'cmd' defined", command.name)
        return false
    end

    local cmd = command.cmd
    local cwd = command.cwd or vim.loop.cwd()

    local opts = {
        cwd = cwd,
        on_stderr = on_event,
        on_stdout = on_event,
        on_exit = on_event,
        stdout_buffered = false,
        stderr_buffered = false,
    }

    job_counter = job_counter + 1
    local job = {
        id = job_counter,
        command = command,
        output = {},
        running = true,
    }

    vim.api.nvim_command('cclose')

    if command.background then
        job.job_id = vim.fn.jobstart(cmd, opts)
    else
        vim.api.nvim_command('tabnew')
        job.job_id = vim.fn.termopen(cmd, opts)
        job.buf_id = vim.fn.bufnr()

        -- Set buffer name to the actual command being run
        local cmdstring = type(cmd) == 'table' and table.concat(cmd, ' ') or cmd
        pcall(vim.api.nvim_buf_set_name, job.buf_id, '[neodo] ' .. (cmdstring or '?'))

        vim.api.nvim_set_option_value('number', false, { scope = 'local' })
        vim.api.nvim_set_option_value('relativenumber', false, { scope = 'local' })
        vim.api.nvim_set_option_value('signcolumn', 'no', { scope = 'local' })
        vim.api.nvim_set_option_value('buflisted', false, { scope = 'local' })
        vim.schedule(function()
            local keys = vim.api.nvim_replace_termcodes('G', true, false, true)
            vim.api.nvim_feedkeys(keys, 'm', false)
        end)
    end

    jobs[job.id] = job

    if command.notify then
        local cmdstring = type(cmd) == 'table' and table.concat(cmd, ' ') or cmd
        notify.info('Running: ' .. cmdstring .. '\nin: ' .. cwd, command.name)
    end

    return true
end

return M
