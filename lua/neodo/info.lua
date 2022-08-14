local M = {}

local projects = require("neodo.projects")

local function print_project_types(project, lines)
    for _, project_type in pairs(project.project_types()) do
        lines[#lines + 1] = '\t\t' .. project_type.name
    end
end

local function print_project(index, project, lines)
    lines[#lines + 1] = index .. ". " .. project.path()
    print_project_types(project, lines)
end

local function print_projects(output, pos)
    local lines = {
        "Loaded projects",
        "---------------",
    }
    local index = 1
    for _, project in pairs(projects) do
        print_project(index, project, lines)
        index = index + 1
    end
    vim.api.nvim_buf_set_lines(output, pos, pos, false, lines)
end

M.show = function()
    -- local current_buffer_project_hash = vim.b.neodo_project_hash
    local height = vim.api.nvim_win_get_height(0) - 10
    local width = vim.api.nvim_win_get_width(0) - 10
    local wincfg = {
        style = "minimal",
        border = "rounded",
        noautocmd = true,
        relative = "editor",
        height = height,
        width = width,
        row = vim.api.nvim_win_get_height(0) / 2 - height / 2 - 1,
        col = vim.api.nvim_win_get_width(0) / 2 - width / 2 - 1,
    }
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.keymap.set("n", "<esc>", function() vim.api.nvim_buf_delete(bufnr, {}) end, { buffer = bufnr })
    vim.keymap.set("n", "q", function() vim.api.nvim_buf_delete(bufnr, {}) end, { buffer = bufnr })
    print_projects(bufnr, 0)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_open_win(bufnr, true, wincfg)
end

return M
