local M = {}

local project_mod = require('neodo.project')
local notify = require('neodo.notify')

local augroup = vim.api.nvim_create_augroup('Neodo', { clear = true })

-- Project type definitions: name -> patterns to detect
local project_type_patterns = {
    cmake = { 'CMakeLists.txt' },
    conan = { 'conanfile.txt', 'conanfile.py' },
    rust = { 'Cargo.toml' },
    node = { 'package.json' },
    git = { '.git' },
    makefile = { 'Makefile' },
    composer = { 'composer.json' },
}

-- Buffers already processed
local processed_bufs = {}

--- Walk directory tree upward and detect project types
local function detect_project_types(start_dir)
    local types = {}
    local dir = start_dir

    while true do
        local data = vim.loop.fs_scandir(dir)
        if data then
            while true do
                local name = vim.loop.fs_scandir_next(data)
                if not name then break end
                for type_key, patterns in pairs(project_type_patterns) do
                    for _, pattern in ipairs(patterns) do
                        if name == pattern then types[type_key] = dir end
                    end
                end
            end
        end

        local parent = vim.fn.fnamemodify(dir, ':h')
        if parent == dir then break end
        dir = parent
    end

    return types
end

--- Find project root (shortest detected type path)
local function find_project_root(types)
    local root = nil
    for _, path in pairs(types) do
        if not root or #path < #root then root = path end
    end
    return root
end

--- Handle a buffer entering
local function handle_buffer(bufnr)
    local ft = vim.bo[bufnr].filetype
    if ft == '' or ft == 'qf' then return end

    local bt = vim.bo[bufnr].buftype
    if bt ~= '' and bt ~= 'nowrite' then return end

    local bufname = vim.api.nvim_buf_get_name(bufnr)
    if bufname == '' then return end

    -- Check if buffer already belongs to a loaded project
    if processed_bufs[bufnr] then
        local project = project_mod.get(processed_bufs[bufnr])
        if project then
            if vim.fn.getcwd() ~= project.root then vim.api.nvim_set_current_dir(project.root) end
            return
        end
    end

    local dir = vim.fn.fnamemodify(bufname, ':h')
    if not dir or dir == '' then return end

    -- Check if this buffer's dir belongs to an already loaded project
    for root, _ in pairs(project_mod.get_all()) do
        if vim.startswith(dir, root) then
            processed_bufs[bufnr] = root
            if vim.fn.getcwd() ~= root then vim.api.nvim_set_current_dir(root) end
            return
        end
    end

    -- Detect project types
    local types = detect_project_types(dir)
    local root = find_project_root(types)
    if not root then return end

    -- Load or get existing project
    local project = project_mod.get(root)
    if not project then project = project_mod.load(root, types) end

    processed_bufs[bufnr] = root
    if vim.fn.getcwd() ~= root then vim.api.nvim_set_current_dir(root) end
end

--- Try to detect and load project from a directory (without needing a buffer)
local function detect_project_from_dir(dir)
    if project_mod.get(dir) then return end

    local types = detect_project_types(dir)
    local root = find_project_root(types)
    if not root then return end

    if not project_mod.get(root) then project_mod.load(root, types) end
end

--- Run a command by key on the current project
function M.run(command_key)
    local project = project_mod.get_current()
    project_mod.run(project, command_key)
end

--- Run last command
function M.run_last()
    local project = project_mod.get_current()
    project_mod.run_last(project)
end

--- Open command picker
function M.neodo()
    local project = project_mod.get_current()
    project_mod.pick_command(project)
end

--- Statusline component
function M.statusline()
    local project = project_mod.get_current()
    if not project then return '' end

    local parts = {}
    for type_key, _ in pairs(project.types) do
        if type_key ~= 'git' then table.insert(parts, type_key) end
    end
    table.sort(parts)

    if #parts == 0 then return '' end

    local status = '[' .. table.concat(parts, '+') .. ']'

    -- Show active cmake profile
    if project.types.cmake and project.config.active then
        status = status .. ' ' .. project.config.active
    end

    return status
end

--- Edit project config
function M.edit_config()
    local project = project_mod.get_current()
    if not project then
        notify.warning('No project loaded')
        return
    end

    local config_path = project.root .. '/.neodo.lua'
    if vim.fn.filereadable(config_path) ~= 1 then
        local content = project_mod.generate_config(project.types)
        vim.fn.writefile(vim.split(content, '\n'), config_path)
    end

    vim.cmd('edit ' .. config_path)
end

--- Get project for buffer
function M.get_project(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local root = processed_bufs[bufnr]
    return root and project_mod.get(root) or nil
end

--- Setup plugin
function M.setup(opts)
    opts = opts or {}

    -- Register additional project type patterns
    if opts.project_types then
        for key, patterns in pairs(opts.project_types) do
            project_type_patterns[key] = patterns
        end
    end

    -- Buffer enter autocommand
    vim.api.nvim_create_autocmd({ 'BufEnter' }, {
        group = augroup,
        pattern = '*',
        callback = function()
            local bufnr = tonumber(vim.fn.expand('<abuf>')) or 0
            vim.schedule(function() handle_buffer(bufnr) end)
        end,
    })

    -- VimEnter - detect project from cwd and process existing buffers
    vim.api.nvim_create_autocmd({ 'VimEnter' }, {
        group = augroup,
        pattern = '*',
        callback = function()
            detect_project_from_dir(vim.loop.cwd())
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                handle_buffer(bufnr)
            end
        end,
    })

    -- DirChanged - detect project when cwd changes
    vim.api.nvim_create_autocmd({ 'DirChanged' }, {
        group = augroup,
        pattern = '*',
        callback = function() detect_project_from_dir(vim.loop.cwd()) end,
    })

    -- Watch for .neodo.lua changes
    vim.api.nvim_create_autocmd('BufWritePost', {
        group = augroup,
        pattern = '*/.neodo.lua',
        callback = function()
            local file = vim.fn.expand('%:p')
            local root = vim.fn.fnamemodify(file, ':h')
            project_mod.reload(root)
            notify.info('Config reloaded', root)
        end,
    })

    -- :Neodo command
    vim.api.nvim_create_user_command('Neodo', function(cmd_opts)
        local arg = cmd_opts.fargs[1]
        if not arg or arg == '' then
            M.neodo()
        else
            M.run(arg)
        end
    end, {
        nargs = '?',
        complete = function()
            local project = project_mod.get_current()
            if not project then return {} end
            local keys = vim.tbl_keys(project.commands)
            table.sort(keys)
            return keys
        end,
    })

    vim.api.nvim_create_user_command('NeodoEditConfig', M.edit_config, {})

    -- Detect project from cwd and process already loaded buffers
    vim.schedule(function()
        detect_project_from_dir(vim.loop.cwd())
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) then handle_buffer(bufnr) end
        end
    end)
end

return M
