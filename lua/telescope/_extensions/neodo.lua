-- Inspiration from:
-- https://github.com/nvim-telescope/telescope-project.nvim
local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then return end

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local telescope_config = require("telescope.config").values
local actions = require("telescope.actions")
local projects = require('neodo.projects')
local log = require('neodo.log')
local runner = require('neodo.runner')

local on_command_selected = function(prompt_bufnr)
    local selection = require'telescope.actions.state'.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    runner.run(selection.value)
end

---Main entrypoint for Telescope.
---@param opts table
local function neodo_entry_point(opts)
    opts = opts or {}

    if vim.b.neodo_project_hash == nil then
        log('Buffer not attached to any project')
        return
    end

    local project = projects[vim.b.neodo_project_hash]
    local results = runner.get_enabled_commands_keys(project)

    if #results ~= 0 then
        pickers.new(opts, {
            prompt_title = "Select NeoDo command",
            finder = finders.new_table({results = results}),
            previewer = false,
            sorter = telescope_config.generic_sorter(opts),
            attach_mappings = function(_, _)
                actions.select_default:replace(on_command_selected)
                return true
            end
        }):find()
    else
        log("No commands defined for current project")
    end

end

return telescope.register_extension({exports = {neodo = neodo_entry_point}})
