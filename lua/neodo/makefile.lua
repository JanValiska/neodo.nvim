local M = {}

--- Parse Makefile and extract targets
local function parse_targets(makefile_path)
    if vim.fn.filereadable(makefile_path) ~= 1 then return {} end

    local targets = {}
    local lines = vim.fn.readfile(makefile_path)
    for _, line in ipairs(lines) do
        local target = line:match('^([a-zA-Z0-9_][a-zA-Z0-9_.%-]*)%s*:')
        if target then
            targets[target] = true
        end
    end
    targets['.PHONY'] = nil
    targets['.DEFAULT'] = nil
    targets['.SUFFIXES'] = nil

    local sorted = vim.tbl_keys(targets)
    table.sort(sorted)
    return sorted
end

function M.commands(project_root)
    local cmds = {}
    local targets = parse_targets(project_root .. '/Makefile')
    for _, target in ipairs(targets) do
        cmds['make_' .. target] = {
            name = 'Make: ' .. target,
            cmd = { 'make', target },
            cwd = project_root,
        }
    end
    return cmds
end

return M
