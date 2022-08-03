local M = {}

local function log(text, category, color)
    local line = text
    if category then
        line = category .. ': ' .. line
    end
    print(line)
end

function M.info(text, category)
    log(text, category, "normal")
end

function M.warning(text, category)
    log(text, category, "normal")
end

function M.error(text, category)
    log(text, category, "normal")
end

return M
