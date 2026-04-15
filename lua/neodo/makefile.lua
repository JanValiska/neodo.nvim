local M = {}

--- Parse Makefile and extract targets
local function parse_targets(makefile_path)
    if vim.fn.filereadable(makefile_path) ~= 1 then return {} end

    local targets = {}
    local lines = vim.fn.readfile(makefile_path)
    for _, line in ipairs(lines) do
        local target = line:match('^([a-zA-Z0-9_][a-zA-Z0-9_.%-]*)%s*:')
        if target then targets[target] = true end
    end
    targets['.PHONY'] = nil
    targets['.DEFAULT'] = nil
    targets['.SUFFIXES'] = nil

    local sorted = vim.tbl_keys(targets)
    table.sort(sorted)
    return sorted
end

function M.commands(config, project_root)
    local make_cfg = (config and config.makefile) or {}
    local cwd = make_cfg.src and (project_root .. '/' .. make_cfg.src) or project_root
    local cmds = {}
    local targets = parse_targets(cwd .. '/Makefile')
    for _, target in ipairs(targets) do
        cmds['make_' .. target] = {
            name = 'Make: ' .. target,
            cmd = { 'make', target },
            cwd = cwd,
        }
    end
    return cmds
end

return M
