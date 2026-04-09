local M = {}

local function notify_impl(text, title, category)
    if title then
        title = "Neodo: " .. title
    else
        title = "Neodo"
    end
    return vim.notify(text, category, { title = title })
end

function M.info(text, header)
    return notify_impl(text, header, vim.log.levels.INFO)
end

function M.warning(text, header)
    return notify_impl(text, header, vim.log.levels.WARN)
end

function M.error(text, header)
    return notify_impl(text, header, vim.log.levels.ERROR)
end

return M
