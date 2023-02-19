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
                    if line == "" then
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

return M
