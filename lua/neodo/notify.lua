local M = {}

local notify = require 'notify'

local notification_timeout = 2500

function M.info(text, header)
    notify(text, nil, {title = header, timeout = notification_timeout})
end

function M.warning(text, header)
    notify(text, 'warning', {title = header, timeout = notification_timeout})
end

function M.error(text, header)
    notify(text, 'error', {title = header, timeout = notification_timeout})
end

return M
