local utils = require('neodo.utils')

local path_sep = vim.loop.os_uname().version:match('Windows') and '\\' or '/'
---@private
local function path_join(...) return table.concat(vim.tbl_flatten({ ... }), path_sep) end
local logfilename = path_join(vim.fn.stdpath('log'), 'neodo.log')
local log_date_format = '%F %H:%M:%S'

local Level = {
    None = 0,
    Error = 1,
    Warning = 2,
    Info = 3,
    Debug = 4,
}

local function log_level() return NeodoLogLevel or Level.Info end

local function log_level_to_string(level)
    if level == Level.None then return 'None' end
    if level == Level.Error then return 'Error' end
    if level == Level.Warning then return 'Warning' end
    if level == Level.Info then return 'Info' end
    if level == Level.Debug then return 'Debug' end
end

local logfile, openerr = nil, nil

local function open_logfile()
    -- Try to open file only once
    if logfile then return true end
    if openerr then return false end

    logfile, openerr = io.open(logfilename, 'a+')
    if not logfile then return false end

    -- Start message for logging
    logfile:write(
        string.format('[%s][STARTUP] NEODO logging initiated\n', os.date(log_date_format))
    )
    return true
end

local function log(...)
    if not logfile then
        local err = open_logfile()
        if err then return end
    end

    local parts = {}
    table.insert(
        parts,
        string.format('[%s][%s]', os.date(log_date_format), log_level_to_string(log_level()))
    )

    utils.tbl_append(parts, { ... })

    logfile:write(table.concat(parts, ' '), '\n')
    logfile:flush()
end

local M = {}

M.level = Level

M.error = function(...)
    if log_level() < Level.Error then return end
    log(...)
end

M.warning = function(...)
    if log_level() < Level.Warning then return end
    log(...)
end

M.info = function(...)
    if log_level() < Level.Info then return end
    log(...)
end

M.debug = function(...)
    if log_level() < Level.Debug then return end
    log(...)
end

return M
