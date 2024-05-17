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
            notify = false,
            fn = function()
                require('neodo').info()
            end,
        },
        show_jobs = {
            name = 'Show jobs',
            notify = false,
            fn = function()
                require('neodo').jobs()
            end,
        },
        edit_project_settings = {
            name = 'Edit project settings',
            notify = false,
            fn = function()
                require('neodo').edit_project_settings()
            end,
            enabled = function()
                return require('neodo').get_project() ~= nil
            end
        },
    }
}

return M
