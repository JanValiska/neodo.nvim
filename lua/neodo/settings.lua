local M = {
    project_type = {},
    qf_open_on_start = false,
    qf_open_on_stop = false,
    qf_open_on_error = true,
    qf_close_on_start = true,
    qf_close_on_success = true,
    terminal_close_on_success = true,
    change_root = true,
    change_root_notify = false,
    load_project_notify = false,
    generic_project_settings = {},
    root_patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" }
}

return M
