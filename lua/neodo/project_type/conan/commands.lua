local M = {}

local utils = require('neodo.utils')
local picker = require('neodo.picker')
local config = require('neodo.project_type.conan.config')
local Path = require('plenary.path')


function M.conan_install(opts)
    opts = opts or {}

    opts.name = opts.name or 'Install'

    opts.enabled = true

    opts.cmd = opts.cmd
        or function(ctx)
            local conan_project = ctx.project_type
            local cmd = { 'conan', 'install' }
                if conan_project.version == 1 then
                    cmd = utils.tbl_append(cmd, { '--profile', profile:get_conan_profile() })
                else
                    cmd = utils.tbl_append(cmd, {
                        '--profile:build=' .. profile:get_conan_profile(),
                        '--profile:host=' .. profile:get_conan_profile(),
                    })
                end
            end
            -- table.insert(cmd, '--build=missing')
            local remote = profile:get_conan_remote()
            if remote then cmd = utils.tbl_append(cmd, { '-r', remote }) end
            cmd = utils.tbl_append(cmd, { '.', '-u' })
            if cmake_project.conan_version == 1 then
                cmd = utils.tbl_append(cmd, { '-if', profile:get_build_dir() })
            elseif cmake_project.conan_version == 2 then
                local output_folder = Path:new(profile:get_build_dir(), 'conan_libs')
                cmd = utils.tbl_append(cmd, { '-of', output_folder:absolute() })
            end
            return cmd
        end

    opts.cwd = opts.cwd or function(ctx) return ctx.project_type.path end

    opts.on_success = opts.on_success
        or function(ctx)
            local cmake_project = ctx.project_type
            if cmake_project.autoconfigure == true then ctx.project:run('cmake.configure') end
        end

    return opts
end

function M.select_conan_profile(opts)
    opts = opts or {}

    opts.name = opts.name or 'Select conan profile'

    opts.enabled = opts.enabled
        or function(ctx) return ctx.project_type.has_conan and M.get_selected_profile(ctx) end

    opts.fn = opts.fn
        or function(ctx)
            local items = utils.get_output('conan profile list')
            if ctx.project_type.conan_version == 2 then table.remove(items, 1) end
            picker.pick('Select conan profile: ', items, function(conan_profile)
                local cmake_project = ctx.project_type
                local profile = functions.get_selected_profile(cmake_project)
                if not profile then return end
                profile:set_conan_profile(conan_profile)
                config.save(ctx.project, cmake_project, function()
                    if cmake_project.conan_auto_install == true then
                        ctx.project:run('cmake.conan_install')
                    elseif cmake_project.autoconfigure == true then
                        ctx.project:run('cmake.configure')
                    end
                end)
            end)
        end

    return opts
end

function M.get_info_node(ctx)
    local NuiTree = require('nui.tree')
    local cmake_project = ctx.project_type

    local nodes = {}
    table.insert(
        nodes,
        NuiTree.Node({
            text = 'Has conan: ' .. (cmake_project.has_conan and 'Yes' or 'No'),
        })
    )

    local selected = functions.get_selected_profile(cmake_project)

    if vim.tbl_count(cmake_project.config.profiles) ~= 0 then
        local profileNodes = {}
        for _, profile in pairs(cmake_project.config.profiles) do
            local profileNode = NuiTree.Node({ text = profile:get_name() }, profile:get_info_node())
            if profile == selected then
                profileNode.text = profileNode.text .. ' (current)'
                profileNode:expand()
            end
            table.insert(profileNodes, profileNode)
        end
        local profiles_node = NuiTree.Node({ text = 'Profiles:' }, profileNodes)
        profiles_node:expand()
        table.insert(nodes, profiles_node)
    else
        table.insert(nodes, 'No profile available')
    end
    return nodes
end

return M
