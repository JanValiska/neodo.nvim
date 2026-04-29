local M = {}

local notify = require('neodo.notify')

local conan_version = nil

function M.detect_version()
    if conan_version then return conan_version end
    local ok, lines = pcall(function()
        local output = vim.fn.system('conan --version')
        return vim.split(output, '\n')
    end)
    if not ok or not lines[1] then return nil end
    local ver = lines[1]:match('(%d+)%.')
    conan_version = ver and tonumber(ver) or nil
    return conan_version
end

function M.has_conanfile(project_root, source_dir)
    local dirs = { project_root }
    if source_dir then table.insert(dirs, project_root .. '/' .. source_dir) end
    for _, dir in ipairs(dirs) do
        if
            vim.fn.filereadable(dir .. '/conanfile.txt') == 1
            or vim.fn.filereadable(dir .. '/conanfile.py') == 1
        then
            return true
        end
    end
    return false
end

--- Build conan install command
--- conan_cfg: { profile, remote, options }
--- source_dir: relative path to conanfile (nil = ".")
--- build_dir: cmake build dir; output goes to build_dir/conan_libs (v2) or build_dir (v1); nil = no output dir
function M.build_install_cmd(conan_cfg, source_dir, build_dir)
    local ver = M.detect_version()
    if not ver then
        notify.error('Conan not found or version detection failed')
        return nil
    end

    local cmd = { 'conan', 'install' }
    local cfg = conan_cfg or {}

    if cfg.profile then
        if ver >= 2 then
            table.insert(cmd, '--profile:build=' .. cfg.profile)
            table.insert(cmd, '--profile:host=' .. cfg.profile)
        else
            table.insert(cmd, '--profile')
            table.insert(cmd, cfg.profile)
        end
    end

    if cfg.remote then
        table.insert(cmd, '-r')
        table.insert(cmd, cfg.remote)
    end

    if cfg.options then
        for _, opt in ipairs(cfg.options) do
            table.insert(cmd, opt)
        end
    end

    table.insert(cmd, source_dir or '.')

    if build_dir then
        if ver >= 2 then
            table.insert(cmd, '-of')
            table.insert(cmd, build_dir .. '/conan_libs')
        else
            table.insert(cmd, '-if')
            table.insert(cmd, build_dir)
        end
    end

    return cmd
end

function M.commands(config, project_root)
    local cfg = config.conan or {}
    local cmd = M.build_install_cmd(cfg, nil, nil)
    if not cmd then return {} end

    return {
        conan_install = {
            name = 'Conan: Install',
            cmd = cmd,
            cwd = project_root,
            notify = true,
        },
    }
end

function M.default_config_lines()
    return {
        '  conan = {',
        '    profile = "default",',
        '    -- remote = "my-remote",',
        '    -- options = {},',
        '  },',
    }
end

return M
