local M = {}
function M.tbl_join(tbl, sep)
    local r = ''
    local size = vim.tbl_count(tbl)
    for i, value in ipairs(tbl) do
        r = r .. value
        if i < size then r = r .. sep end
    end
    return r
end

function M.split(vertical, bufnr)
    local cmd = vertical and "vsplit" or "split"

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
    local cmd = vertical and "vertical resize " or "resize"
    cmd = cmd .. amount

    vim.cmd(cmd)
end

function M.delete_buf(bufnr)
    if bufnr ~= nil then vim.api.nvim_buf_delete(bufnr, {force = true}) end
end

function M.close_win(winnr)
    if winnr ~= nil then vim.api.nvim_win_close(winnr, {force = true}) end
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
return M
