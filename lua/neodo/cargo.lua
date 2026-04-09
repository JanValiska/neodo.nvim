local M = {}

function M.commands(project_root)
    return {
        cargo_build = {
            name = 'Cargo: build',
            cmd = { 'cargo', 'build' },
            cwd = project_root,
        },
        cargo_build_release = {
            name = 'Cargo: build (release)',
            cmd = { 'cargo', 'build', '--release' },
            cwd = project_root,
        },
        cargo_run = {
            name = 'Cargo: run',
            cmd = { 'cargo', 'run' },
            cwd = project_root,
        },
        cargo_test = {
            name = 'Cargo: test',
            cmd = { 'cargo', 'test' },
            cwd = project_root,
        },
        cargo_check = {
            name = 'Cargo: check',
            cmd = { 'cargo', 'check' },
            cwd = project_root,
        },
        cargo_clippy = {
            name = 'Cargo: clippy',
            cmd = { 'cargo', 'clippy' },
            cwd = project_root,
        },
        cargo_clean = {
            name = 'Cargo: clean',
            cmd = { 'cargo', 'clean' },
            cwd = project_root,
        },
    }
end

return M
