local M = {}

local projects = require('neodo.projects')
local log = require 'neodo.log'

function M.pick_command()
    local project = projects[vim.b.neodo_project_hash]
    local results = project.get_commands_keys_names()

    local function show_nice_name(item)
        return item.name
    end

    if #results ~= 0 then
        vim.ui.select(results, { format_item = show_nice_name, prompt = "Select project command", kind = "neodo.select" }
            , function(selection)
            if selection == nil then
                return
            end
            project.run(selection.key)
        end)
    else
        log.warning("No commands defined for current project")
    end
end

function M.pick(title, items, on_select)
    vim.ui.select(items, { prompt = title, kind = 'neodo.select' }, function(selection)
        if selection == nil then
            return
        end
        on_select(selection)
    end)
end

return M
