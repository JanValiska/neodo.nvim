local M = {}

--- Detect package manager from lockfiles
local function detect_package_manager(project_root)
    if
        vim.fn.filereadable(project_root .. '/bun.lockb') == 1
        or vim.fn.filereadable(project_root .. '/bun.lock') == 1
    then
        return 'bun'
    elseif vim.fn.filereadable(project_root .. '/pnpm-lock.yaml') == 1 then
        return 'pnpm'
    elseif vim.fn.filereadable(project_root .. '/yarn.lock') == 1 then
        return 'yarn'
    end
    return 'npm'
end

function M.commands(config, project_root)
    local node_cfg = (config and config.node) or {}
    local cwd = node_cfg.src and (project_root .. '/' .. node_cfg.src) or project_root

    local pkg_path = cwd .. '/package.json'
    if vim.fn.filereadable(pkg_path) ~= 1 then return {} end

    local ok, pkg = pcall(function()
        local data = table.concat(vim.fn.readfile(pkg_path), '\n')
        return vim.fn.json_decode(data)
    end)
    if not ok or not pkg then return {} end

    local pm = detect_package_manager(cwd)
    local run_prefix = pm == 'npm' and { pm, 'run' } or { pm }
    local pm_label = pm:sub(1, 1):upper() .. pm:sub(2)

    local cmds = {}

    cmds.npm_install = {
        name = pm_label .. ': install',
        cmd = { pm, 'install' },
        cwd = cwd,
    }

    if pkg.scripts then
        for script, _ in pairs(pkg.scripts) do
            local cmd = vim.list_extend({}, run_prefix)
            table.insert(cmd, script)
            cmds['npm_' .. script] = {
                name = pm_label .. ': ' .. script,
                cmd = cmd,
                cwd = cwd,
            }
        end
    end

    return cmds
end

return M
