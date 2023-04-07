local M = {}

local NuiTree = require('nui.tree')
local NuiLine = require('nui.line')

local function make_popup()
    local NuiPopup = require('nui.popup')
    return NuiPopup({
        position = '50%',
        size = {
            width = 120,
            height = 40,
        },
        enter = true,
        focusable = true,
        zindex = 50,
        relative = 'editor',
        border = {
            padding = {
                top = 2,
                bottom = 2,
                left = 3,
                right = 3,
            },
            style = 'rounded',
            text = {
                top = ' Neodo info page ',
            },
        },
        buf_options = {
            modifiable = true,
            readonly = false,
        },
        win_options = {
            winhighlight = 'FloatBorder:FloatBorder,FloatBorder:FloatBorder',
        },
    })
end

M.show = function(projects)
    local function get_project(project)
        local ptNodes = {}
        local project_types = project:get_project_types()
        if vim.tbl_count(project_types) ~= 0 then
            for _, t in pairs(project_types) do
                if type(t.get_info_node) == 'function' then
                    local ptNode = NuiTree.Node(
                        { text = t.name },
                        t.get_info_node({ project = project, project_type = t })
                    )
                    ptNode:expand()
                    table.insert(ptNodes, ptNode)
                else
                    table.insert(ptNodes, NuiTree.Node({ text = t.name }))
                end
            end
        end
        return NuiTree.Node({ text = project:get_path() }, ptNodes)
    end

    local function get_project_list()
        local project_list = {}
        for _, project in pairs(projects) do
            local project_node = get_project(project)
            project_node:expand()
            table.insert(project_list, project_node)
        end
        return project_list
    end

    local popup = make_popup()
    popup:mount()

    local projects_node = NuiTree.Node({ text = 'Projects' }, get_project_list())
    projects_node:expand()

    local tree = NuiTree({
        winid = popup.winid,
        nodes = { projects_node },
        prepare_node = function(node)
            local line = NuiLine()

            line:append(string.rep('  ', node:get_depth() - 1))

            if node:has_children() then
                line:append(node:is_expanded() and ' ' or ' ', 'SpecialChar')
            else
                line:append('  ')
            end

            line:append(node.text)

            return line
        end,
    })

    -- for _, node in pairs(tree.nodes.by_id) do
    --     node:expand()
    -- end

    local event = require('nui.utils.autocmd').event
    popup:on({ event.BufLeave }, function() popup:unmount() end, { once = true })

    popup:on({ event.BufWinLeave }, function()
        vim.schedule(function() popup:unmount() end)
    end, { once = true })

    local map_options = { noremap = true }

    -- quit
    popup:map('n', 'q', function() popup:unmount() end, map_options)

    -- collapse
    popup:map('n', '<cr>', function()
        local node, linenr = tree:get_node()
        if not node:has_children() then
            node, linenr = tree:get_node(node:get_parent_id())
        end
        if node then
            if node:is_expanded() then
                node:collapse()
            else
                node:expand()
            end
            vim.api.nvim_win_set_cursor(popup.winid, { linenr, 0 })
            tree:render()
        end
    end, map_options)

    tree:render()
end

return M
