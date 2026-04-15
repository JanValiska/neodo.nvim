local M = {}

function M.commands(config, project_root)
    local rust_cfg = (config and config.rust) or {}
    local cwd = rust_cfg.src and (project_root .. '/' .. rust_cfg.src) or project_root
    return {
        cargo_build = {
            name = 'Cargo: build',
            cmd = { 'cargo', 'build' },
            cwd = cwd,
        },
        cargo_build_release = {
            name = 'Cargo: build (release)',
            cmd = { 'cargo', 'build', '--release' },
            cwd = cwd,
        },
        cargo_run = {
            name = 'Cargo: run',
            cmd = { 'cargo', 'run' },
            cwd = cwd,
        },
        cargo_test = {
            name = 'Cargo: test',
            cmd = { 'cargo', 'test' },
            cwd = cwd,
        },
        cargo_check = {
            name = 'Cargo: check',
            cmd = { 'cargo', 'check' },
            cwd = cwd,
        },
        cargo_clippy = {
            name = 'Cargo: clippy',
            cmd = { 'cargo', 'clippy' },
            cwd = cwd,
        },
        cargo_clean = {
            name = 'Cargo: clean',
            cmd = { 'cargo', 'clean' },
            cwd = cwd,
        },
    }
end

return M
