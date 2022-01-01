local M = {}

local projects = require('neodo.projects')
local runner = require('neodo.runner')
local log = require'neodo.log'

function M.pick()
    local project = projects[vim.b.neodo_project_hash]
    local results = runner.get_enabled_commands_keys(project)
    if #results ~= 0 then
        vim.ui.select(results, {}, function(selection)
            runner.run(selection)
        end)
    else
        log("No commands defined for current project")
    end
end

return M
