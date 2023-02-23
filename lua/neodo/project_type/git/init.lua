local M = {}

M.register = function()
    local settings = require('neodo.settings')
    settings.project_types.git = {
        name = 'Git',
        patterns = { '.git' },
        commands = {
            neogit = {
                name = "Show Neogit window",
                fn = function()
                    vim.cmd('Neogit')
                end,
            },
        },
        get_info_node = function(_)
            local NuiTree = require('nui.tree')
            return {
                NuiTree.Node({
                    text = 'State: TODO(dirty, clean, number of changes, etc)',
                }),
                NuiTree.Node({ text = 'Branch: TODO' }),
                NuiTree.Node({ text = 'Upstream branch: TODO' }),
                NuiTree.Node(
                    { text = 'Remotes: TODO' },
                    {
                        NuiTree.Node({ text = 'remote1 TODO' }),
                        NuiTree.Node({ text = 'remote2 TODO' }),
                    }
                ),
            }
        end,
    }
end

return M
