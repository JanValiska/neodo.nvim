local M = {}

local projects = require('neodo.projects')
local runner = require('neodo.runner')
local log = require'neodo.log'

function M.pick_command()
    local project = projects[vim.b.neodo_project_hash]
    local results = runner.get_enabled_commands_keys(project)
    if #results ~= 0 then
        vim.ui.select(results, {prompt = "Select project command", kind="neodo.select"}, function(selection)
            if selection == nil then
                return
            end
            runner.run(selection)
        end)
    else
        log.warning("No commands defined for current project")
    end
end

function M.pick(title, items, on_select)
    vim.ui.select(items, {prompt = title, kind='neodo.select'}, function(selection)
        if selection == nil then
            return
        end
        on_select(selection)
    end)
end

return M
