local M = {
    project_types = {},
    terminal_close_on_success = true,
    terminal_close_on_error = true,
    change_root = true,
    change_root_notify = false,
    load_project_notify = false,
    use_in_the_source_config = false,
    commands = {
        show_neodo_info = {
            name = 'Show neodo info',
            fn = function()
                require('neodo.info').show()
            end,
        },
    },
}

return M
