local M = {}

local notify = require 'notify'

-- local notification = require("neogit.lib.notification")
local notification_timeout = 2500

function M.info(text, header)
    -- notification.create("TEST")
    notify(text, nil, {title = header, timeout = notification_timeout})
end
-- local function notify_warning(text, header) notify(text, 'warning', {title = header, timeout = notification_timeout}) end
--
function M.error(text, header)
    notify(text, 'error', {title = header, timeout = notification_timeout})
end

return M
