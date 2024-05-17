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
                top = ' Neodo Jobs',
            },
        },
        buf_options = {
            modifiable = true,
            readonly = false,
            filetype = 'neodo-jobs',
        },
        win_options = {
            winhighlight = 'FloatBorder:FloatBorder,FloatBorder:FloatBorder',
        },
    })
end

M.show = function()
    local runner = require('neodo.runner')
    local jobs = runner.get_jobs()

    local function get_job_info(job)
        local jobInfoNode = {}
        local jobType = 'Command'
        if job.command.fn and type(job.command.fn) == 'function' then jobType = 'Function' end
        table.insert(jobInfoNode, NuiTree.Node({ text = 'Type: ' .. jobType }, {}))
        table.insert(jobInfoNode, NuiTree.Node({ text = 'UUID: ' .. job.uuid }, {}))
        if not job.running and job.result then
            table.insert(jobInfoNode, NuiTree.Node({ text = 'Result: ' .. job.result }, {}))
        end
        return jobInfoNode
    end

    local function get_jobs_node(running, category_name)
        local jobsNodes = {}
        if vim.tbl_count(jobs) ~= 0 then
            for _, job in pairs(jobs) do
                if running then
                    if job.running then
                        local runningJob =
                            NuiTree.Node({ text = job.command.name }, get_job_info(job))
                        runningJob:expand()
                        table.insert(jobsNodes, runningJob)
                    end
                else
                    if not job.running then
                        local finishedJobNode =
                            NuiTree.Node({ text = job.command.name }, get_job_info(job))
                        finishedJobNode:expand()
                        table.insert(jobsNodes, finishedJobNode)
                    end
                end
            end
        end
        local node = NuiTree.Node({ text = category_name }, jobsNodes)
        node:expand()
        return node
    end

    local jobsNodes = {}
    table.insert(jobsNodes, get_jobs_node(true, 'Running'))
    table.insert(jobsNodes, get_jobs_node(false, 'Finished'))
    local allJobs = NuiTree.Node({ text = 'Jobs' }, jobsNodes)
    allJobs:expand()

    local popup = make_popup()
    popup:mount()

    local tree = NuiTree({
        winid = popup.winid,
        nodes = { allJobs },
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
