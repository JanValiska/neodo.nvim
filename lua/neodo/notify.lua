local M = {}

local notify = require("notify")

local notification_timeout = 2500

function M.info(text, header)
	vim.schedule(function()
		notify(text, nil, { title = header, timeout = notification_timeout })
	end)
end

function M.warning(text, header)
	vim.schedule(function()
		notify(text, "warning", { title = header, timeout = notification_timeout })
	end)
end

function M.error(text, header)
	vim.schedule(function()
		notify(text, "error", { title = header, timeout = notification_timeout })
	end)
end

return M
