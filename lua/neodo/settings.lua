local M = {
    project_type = {
        vim = {
            patterns = {'init.lua', 'init.vim'},
            on_attach = nil,
            commands = {
                packer_compile = {
                    name = "Compile packer",
                    cmd = function()
                        require'packer'.compile()
                    end
                }
            }
        },
        cmake = {
            patterns = {'CMakeLists.txt'},
            on_attach = nil,
            commands = {
                build = {
                    name = "CMake Build",
                    cmd = 'cmake --build build-debug',
                    errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
                },
                configure = {
                    name = "CMake Configure",
                    cmd = 'cmake -B build-debug',
                    errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
                }
            }
        },
        mongoose = {
            commands = {
                build = {
                    name = "Build",
                    cmd = 'mos build --platform esp32 --local',
                    errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
                },
                flash = {
                    name = "Flash",
                    cmd = 'mos flash',
                    errorformat = '%.%#'
                }
            },
            patterns = {'mos.yml'},
            on_attach = nil
        }
    },
    qf_open_on_start = false,
    qf_open_on_stop = false,
    qf_open_on_error = true,
    qf_close_on_start = true,
    qf_close_on_success = true,
    terminal_close_on_success = true
}

return M
