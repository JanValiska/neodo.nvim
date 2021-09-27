-- Inspiration from:
-- https://github.com/nvim-telescope/telescope-project.nvim
local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then return end

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local telescope_config = require("telescope.config").values
local actions = require("telescope.actions")
local entry_display = require("telescope.pickers.entry_display")
local projects = require('neodo.projects')
local log = require('neodo.log')
local neodo = require('neodo')

local on_command_selected = function(prompt_bufnr)
    local selection = actions.get_selected_entry(prompt_bufnr)
    actions.close(prompt_bufnr)
    neodo.run(selection.value)
end

---Main entrypoint for Telescope.
---@param opts table
local function neodo_entry_point(opts)
    opts = opts or {}

    if vim.b.project_hash == nil then
        log('Buffer not attached to any project')
        return
    end

    local project = projects[vim.b.project_hash]
    local results = neodo.get_enabled_commands_keys(project)

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
end

return telescope.register_extension({exports = {neodo = neodo_entry_point}})
