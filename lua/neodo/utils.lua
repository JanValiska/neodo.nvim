local M = {}
function M.tbl_join(tbl, sep)
    local r = ''
    local size = vim.tbl_count(tbl)
    for i, value in ipairs(tbl) do
        r = r .. value
        if i < size then
            r = r .. sep
        end
    end
    return r
end

function M.split(vertical, bufnr)
    local cmd = vertical and 'vsplit' or 'split'

    vim.cmd(cmd)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    return win
end

function M.belowright_split(bufnr)
    vim.cmd('belowright split')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    return win
end

function M.aboveleft_split(bufnr)
    vim.cmd('aboveleft split')
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)
    return win
end

function M.resize(vertical, amount)
    local cmd = vertical and 'vertical resize ' or 'resize'
    cmd = cmd .. amount

    vim.cmd(cmd)
end

function M.delete_buf(bufnr)
    if bufnr ~= nil then
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end
end

function M.close_win(winnr)
    if winnr ~= nil then
        vim.api.nvim_win_close(winnr, { force = true })
    end
end

function M.get_buf_variable(buf, var_name)
    local s, v = pcall(function()
        return vim.api.nvim_buf_get_var(buf, var_name)
    end)
    if s then
        return v
    else
        return nil
    end
end

function M.split_string(inputstr, delimiter)
    if delimiter == nil then
        delimiter = '%s'
    end
    local t = {}
    for str in string.gmatch(inputstr, '([^' .. delimiter .. ']+)') do
        table.insert(t, str)
    end
    return t
end

function M.get_output(command)
    local output_lines = {}

    local function on_output(_, data, event)
        if event == 'stdout' or event == 'stderr' then
            if data then
                for _, line in ipairs(data) do
                    -- strip dos line endings
                    line = line:gsub('\r', '')
                    -- strip ANSI color codes
                    line = line:gsub('\27%[[0-9;mK]+', '')
                    if line == '' then
                        goto continue
                    end
                    table.insert(output_lines, line)
                    ::continue::
                end
            end
            return
        end
    end

    local opts = {
        on_stderr = on_output,
        on_stdout = on_output,
        stdout_buffered = false,
        stderr_buffered = false,
    }

    local jid = vim.fn.jobstart(command, opts)
    vim.fn.jobwait({ jid })
    return output_lines
end

M.lines_insert_indented = function(lines, line, indent_level)
    local indent_level = indent_level or 1
    local indent_string = ''
    for i = 1, indent_level do
        indent_string = indent_string .. '\t'
    end
    table.insert(lines, indent_string .. line)
end

local function tbl_extend(behavior, deep_extend, ...)
    if behavior ~= 'error' and behavior ~= 'keep' and behavior ~= 'force' then
        error('invalid "behavior": ' .. tostring(behavior))
    end

    if select('#', ...) < 2 then
        error('wrong number of arguments (given ' .. tostring(1 + select('#', ...)) .. ', expected at least 3)')
    end

    local ret = {}
    if vim._empty_dict_mt ~= nil and getmetatable(select(1, ...)) == vim._empty_dict_mt then
        ret = vim.empty_dict()
    end

    for i = 1, select('#', ...) do
        local tbl = select(i, ...)
        vim.validate({ ['after the second argument'] = { tbl, 't' } })
        if tbl then
            for k, v in pairs(tbl) do
                if type(v) == 'table' and deep_extend and not vim.tbl_islist(v) then
                    ret[k] = tbl_extend(behavior, true, ret[k] or vim.empty_dict(), v)
                elseif type(v) == 'table' and vim.tbl_islist(v) and not vim.tbl_isempty(v) then
                    ret[k] = vim.list_extend(ret[k] or {}, v)
                elseif behavior ~= 'force' and ret[k] ~= nil then
                    if behavior == 'error' then
                        error('key found in more than one map: ' .. k)
                    end -- Else behavior is "keep".
                else
                    ret[k] = v
                end
            end
        end
    end
    return ret
end

function M.tbl_extend(behavior, ...)
    return tbl_extend(behavior, false, ...)
end

function M.tbl_deep_extend(behavior, ...)
    return tbl_extend(behavior, true, ...)
end

return M
