local M = {}

local function notify_impl(text, title, category)
    if title then
        title = "Neodo: " .. title
    else
        title = "Neodo"
    end
    vim.notify(text, category, { title = title })
end

function M.info(text, header)
    notify_impl(text, header, vim.log.levels.INFO)
end

function M.warning(text, header)
    notify_impl(text, header, vim.log.levels.WARN)
end

function M.error(text, header)
    notify_impl(text, header, vim.log.levels.ERROR)
end

return M
