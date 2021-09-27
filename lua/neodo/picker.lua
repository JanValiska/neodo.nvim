local M = {}

local has_telescope, _ = pcall(require, "telescope")

if not has_telescope then return end

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local telescope_config = require("telescope.config").values
local actions = require("telescope.actions")

---Main entrypoint for Telescope.
---@param opts table
function M.pick(title, results, selected_handler, opts)
    opts = opts or {}

    local on_command_selected = function(prompt_bufnr)
        local selection = actions.get_selected_entry(prompt_bufnr)
        actions.close(prompt_bufnr)
        selected_handler(selection.value)
    end

    pickers.new(opts, {
        prompt_title = title,
        finder = finders.new_table({results = results}),
        previewer = false,
        sorter = telescope_config.generic_sorter(opts),
        attach_mappings = function(_, _)
            actions.select_default:replace(on_command_selected)
            return true
        end
    }):find()
end

return M
