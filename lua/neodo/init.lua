local M = {}

local utils = require 'neodo.utils'

-- list of currently running jobs
local system_jobs = {}

-- key/value store for lines produced by currently running jobs
local system_jobs_lines = {}

local notify = require 'notify'
-- local notification = require("neogit.lib.notification")
local notification_timeout = 2500

local latest_buf_id = nil

local latest_win_id = nil

-- default plugin settings
local settings = {
    project_type = {
        vim = {
            patterns = {'init.lua', 'init.vim'},
            on_attach = nil,
            commands = {
                packer_compile = {
                    name = "Compile packer",
                    cmd = function()
                        require'packer'.compile()
                    end
                }
            }
        },
        cmake = {
            patterns = {'CMakeLists.txt'},
            on_attach = nil,
            commands = {
                build = {
                    name = "CMake Build",
                    cmd = 'cmake --build build-debug',
                    errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
                },
                configure = {
                    name = "CMake Configure",
                    cmd = 'cmake -B build-debug',
                    errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
                }
            }
        },
        mongoose = {
            commands = {
                build = {
                    name = "Build",
                    cmd = 'mos build --platform esp32 --local',
                    errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
                },
                flash = {
                    name = "Flash",
                    cmd = 'mos flash',
                    errorformat = '%.%#'
                }
            },
            patterns = {'mos.yml'},
            on_attach = nil
        }
    },
    qf_open_on_start = false,
    qf_open_on_stop = false,
    qf_open_on_error = true,
    qf_close_on_start = true,
    qf_close_on_success = true,
    terminal_close_on_success = true
}

local function notify_info(text, header)
    -- notification.create("TEST")
    notify(text, nil, {title = header, timeout = notification_timeout})
end
-- local function notify_warning(text, header) notify(text, 'warning', {title = header, timeout = notification_timeout}) end
local function notify_error(text, header)
    notify(text, 'error', {title = header, timeout = notification_timeout})
end

-- TODO: use something portable to make parent directory
local function get_parent_path(path)
    local pattern = "^(.+)/"
    return string.match(path, pattern)
end

local function directory_find_backwards(path, file)
    while true do
        local data = vim.loop.fs_scandir(path)
        if not data then return nil end
        local function iter() return vim.loop.fs_scandir_next(data) end
        for name, _ in iter do if name == file then return path end end
        path = get_parent_path(path)
        if path == nil then break end
    end
    return nil
end

-- local paths_cache = {}

-- local function known_path(path)
--     for key, item in pairs(paths_cache) do
--         if key == path then return item end
--     end
--     return nil;
-- end

local function get_project_dir_and_type(path)
    -- local cached = known_path(path)
    -- if cached then return cached end

    for type, value in pairs(settings.project_type) do
        for _, pattern in ipairs(value.patterns) do
            local dir = directory_find_backwards(path, pattern)
            if dir then
                -- paths_cache[path] = {dir = dir, type = type}
                return {dir = dir, type = type}
            end
        end
    end
end

function M.buffer_entered()
    local ft = vim.bo.filetype
    if ft == '' then
        return
    end
    local basepath = vim.fn.expand(vim.fn.expand('%:p:h'))
    if basepath == nil then return end
    local p = get_project_dir_and_type(basepath)
    if p ~= nil then
        local dir = p.dir
        local type = p.type
        local project_settings = settings.project_type[type]
        if project_settings ~= nil then
            if project_settings.on_attach ~= nil then
                vim.b.project_type = type
                vim.b.project_dir = dir
                project_settings.on_attach(dir)
            end
        end
    end
end

local function on_command_success(command, return_code)
    local text = command.name .. ' SUCCESS(' .. return_code .. ')'
    notify_info('OK', text)
    if not command.run_as_background_job and settings.terminal_close_on_success then
        utils.close_win(latest_win_id)
    end
    if settings.qf_close_on_success then vim.api.nvim_command("cclose") end
end

local function on_command_failed(command, return_code)
    local text = command.name .. ' FAILED(' .. return_code .. ')'
    notify_error('NOK', text)
    if settings.qf_open_on_error then vim.api.nvim_command("copen") end
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
        if settings.qf_open_on_stop then vim.api.nvim_command("copen") end

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
    if settings.qf_open_on_start then vim.api.nvim_command("copen") end
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
        stderr_buffered = false,
    })

    vim.cmd('keepalt file ' .. 'NeoDo: ' .. expanded_cmd)

    system_jobs[job_id] = command
    system_jobs_lines[job_id] = {}

    local text = command.name .. ' STARTED IN TERMINAL'
    notify_info(expanded_cmd, text)
end

local function start_command(command)
    if settings.qf_close_on_start then vim.api.nvim_command("cclose") end
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

function M.run(command_key)
    local command =
        settings.project_type[vim.b.project_type].commands[command_key]
    start_command(command)
end

function M.setup(config)
    if config then settings = vim.tbl_deep_extend('force', settings, config) end
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
end

return M
