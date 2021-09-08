local M = {}

M.register = function()
    local settings = require 'neodo.settings'
    settings.project_type.cmake = {
        patterns = {'CMakeLists.txt'},
        on_attach = nil,
        commands = {
            build = {
                type = 'terminal',
                name = "CMake Build",
                cmd = 'cmake --build build-debug',
                errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
            },
            configure = {
                type = 'terminal',
                name = "CMake Configure",
                cmd = 'cmake -B build-debug',
                errorformat = [[%f:%l:%c:\ %trror:\ %m,%f:%l:%c:\ %tarning:\ %m,%f:%l:\ %tarning:\ %m,%-G%.%#,%.%#]]
            }
        }
    }
end

return M
