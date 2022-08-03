local M = {}

local notify = require("notify")

local notification_timeout = 2500

local function notify_impl(text, header, category)
    if header then
        header = "Neodo: " .. header
    end
    vim.schedule(function()
        notify(text, category, { title = header, timeout = notification_timeout })
    end)
end

function M.info(text, header)
    notify_impl(text, header, nil)
end

function M.warning(text, header)
    notify_impl(text, header, "warning")
end

function M.error(text, header)
    notify_impl(text, header, "error")
end

return M
