local M = {
    project_type = {},
    terminal_close_on_success = true,
    terminal_close_on_error = true,
    change_root = true,
    change_root_notify = false,
    load_project_notify = false,
    generic_project_settings = {},
    root_patterns = { ".git", "_darcs", ".hg", ".bzr", ".svn", "Makefile", "package.json" }
}

return M
