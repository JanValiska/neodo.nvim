local M = {}

local utils = require('neodo.utils')
local fs = require('neodo.file')
local picker = require('neodo.picker')
local config = require('neodo.project_type.cmake.config')
local functions = require('neodo.project_type.cmake.functions')
local notify = require('neodo.notify')
local Profile = require('neodo.project_type.cmake.profile')

function M.create_profile(ctx)
    local cmake_project = ctx.project_type

    local function check_profile_name_already_exists(name)
        for _, profile in pairs(cmake_project.config.profiles) do
            if name == profile:get_name() then
                return true
            end
        end
        return false
    end

    local function check_profile_with_build_directory_already_exists(directory)
        for _, profile in pairs(cmake_project.config.profiles) do
            if directory == profile:get_build_dir() then
                return true
            end
        end
        return false
    end

    picker.pick('Select build type: ', { 'Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel' }, function(build_type)
        if cmake_project.build_configurations then
            local create_profile = function(build_configuration_key)
                local function ask_profile_name(name)
                    vim.ui.input({ prompt = 'Profile name', default = name }, function(confirmed_name)
                        if not confirmed_name then
                            notify.warning('Profile name selection canceled.')
                            return
                        end

                        if check_profile_name_already_exists(confirmed_name) then
                            notify.warning('Profile with same name already exists. Try new one.')
                            ask_profile_name(confirmed_name)
                            return
                        end

                        local function ask_build_directory(build_directory)
                            vim.ui.input({
                                prompt = 'Build directory',
                                default = build_directory,
                            }, function(confirmed_directory)
                                if not confirmed_directory then
                                    notify.warning('Build directory selection canceled.')
                                    return
                                end

                                if check_profile_with_build_directory_already_exists(confirmed_directory) then
                                    notify.warning('Profile with same build directory already exists. Try new one.')
                                    ask_build_directory(confirmed_directory)
                                    return
                                end

                                local profile = Profile:new(cmake_project)
                                profile:load_default(
                                    confirmed_name,
                                    confirmed_directory,
                                    build_type,
                                    build_configuration_key
                                )
                                local profile_key = profile:get_key()
                                cmake_project.config.profiles[profile_key] = profile
                                cmake_project.config.selected_profile = profile_key
                                notify.info("New profile '" .. profile:get_name() .. "' selected as active")
                                config.save(ctx.project, cmake_project, function()
                                    if cmake_project.has_conan then
                                        if profile:has_conan_profile() then
                                            ctx.project.run('cmake.conan_install')
                                        else
                                            ctx.project.run('cmake.select_conan_profile')
                                        end
                                    elseif cmake_project.autoconfigure == true then
                                        ctx.project.run('cmake.configure')
                                    end
                                end)
                            end)
                        end
                        local suggested_build_directory = 'build-'
                            .. build_type
                            .. '-'
                            .. string.gsub(build_configuration_key, '%s+', '-')
                        ask_build_directory(suggested_build_directory)
                    end)
                end
                local suggested_name = build_type
                    .. '-'
                    .. cmake_project.build_configurations[build_configuration_key].name
                ask_profile_name(suggested_name)
            end

            -- in case that there is only one build configuration
            if vim.tbl_count(cmake_project.build_configurations) == 1 then
                for key, _ in pairs(cmake_project.build_configurations) do
                    create_profile(key)
                    return
                end
            end

            -- otherwise pick configuration
            local function format_build_configuration(item)
                return cmake_project.build_configurations[item].name
            end
            picker.pick(
                'Select build configuration:',
                vim.tbl_keys(cmake_project.build_configurations),
                create_profile,
                format_build_configuration
            )
        else
            notify.error('No build configurations found. Check config/instalation.')
        end
    end)
end

function M.select_profile(ctx)
    local cmake_project = ctx.project_type
    local function format_names(profile_key)
        return cmake_project.config.profiles[profile_key]:get_name()
    end
    picker.pick('Select profile: ', vim.tbl_keys(cmake_project.config.profiles), function(profile_key)
        cmake_project.config.selected_profile = profile_key
        local profile = cmake_project.config.profiles[profile_key]
        functions.switch_compile_commands(profile)
        config.save(ctx.project, cmake_project)
    end, format_names)
end

function M.select_profile_enabled(ctx)
    return vim.tbl_count(ctx.project_type.config.profiles) ~= 0
end

function M.delete_profile(ctx)
    local cmake_project = ctx.project_type
    local function format_names(profile_key)
        return cmake_project.config.profiles[profile_key]:get_name()
    end
    picker.pick('Select profile to delete: ', vim.tbl_keys(cmake_project.config.profiles), function(profile_key)
        local profile = cmake_project.config.profiles[profile_key]
        fs.delete(profile:get_build_dir())
        cmake_project.config.profiles[profile_key] = nil
        if profile_key == cmake_project.config.selected_profile then
            cmake_project.config.selected_profile = nil
        end
        config.save(ctx.project, cmake_project)
    end, format_names)
end

function M.delete_profile_enabled(ctx)
    return vim.tbl_count(ctx.project_type.config.profiles) ~= 0
end

function M.select_target(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return false
    end
    picker.pick('Select target: ', vim.tbl_keys(profile:get_targets()), function(target)
        profile:select_target(target)
        config.save(ctx.project, cmake_project)
    end)
end

function M.select_target_enabled(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return false
    end
    return profile:is_configured() and vim.tbl_count(profile:get_targets()) ~= 0
end

function M.clean(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return nil
    end
    return profile:get_clean_command()
end

function M.clean_enabled(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return false
    end
    return profile:is_configured()
end

function M.build_all(ctx)
    local cmake_project = ctx.project_type
    local profile = cmake_project.config.profiles[cmake_project.config.selected_profile]
    return profile:get_build_all_command()
end

function M.build_all_enabled(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if profile == nil then
        return false
    end
    return profile:is_configured()
end

function M.configure(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return
    end
    return profile:get_configure_command()
end

function M.configure_enabled(ctx)
    local cmake_project = ctx.project_type
    local function conan_installed()
        local profile = functions.get_selected_profile(cmake_project)
        if profile == nil then
            return false
        end
        if cmake_project.has_conan then
            return fs.file_exists(profile:get_build_dir() .. '/conan.lock')
        end
        return true
    end

    return (cmake_project.config.selected_profile ~= nil) and conan_installed()
end

function M.configure_on_success(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return
    end
    profile:set_configured()
    functions.switch_compile_commands(profile)
    config.save(ctx.project, cmake_project)
end

function M.build_selected_target(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return
    end
    return profile:get_build_selected_target_command()
end

function M.build_selected_target_enabled(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return
    end
    return profile:has_selected_target()
end

function M.run_selected_target(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return
    end
    return fs.join_path(profile:get_build_dir(), profile:get_selected_target().paths[1])
end

function M.run_selected_target_enabled(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return false
    end
    return profile:has_selected_target() and profile:get_selected_target().type == 'EXECUTABLE'
end

function M.select_conan_profile(ctx)
    local cmake_project = ctx.project_type
    picker.pick('Select conan profile: ', utils.get_output('conan profile list'), function(conan_profile)
        local profile = functions.get_selected_profile(cmake_project)
        if not profile then
            return
        end
        profile:set_conan_profile(conan_profile)
        config.save(ctx.project, cmake_project)

        if cmake_project.conan_auto_install == true then
            ctx.project.run('cmake.conan_install')
        elseif cmake_project.autoconfigure == true then
            ctx.project.run('cmake.configure')
        end
    end)
end

function M.select_conan_profile_enabled(ctx)
    local cmake_project = ctx.project_type
    return cmake_project.has_conan and cmake_project.config.selected_profile
end

function M.conan_install(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return
    end
    local conan_profile = ''
    if profile:has_conan_profile() then
        conan_profile = '--profile ' .. profile:get_conan_profile()
    end
    return 'conan install ' .. conan_profile .. ' -if ' .. profile:get_build_dir() .. ' .'
end

function M.conan_install_on_success(ctx)
    local cmake_project = ctx.project_type
    if cmake_project.autoconfigure == true then
        ctx.project.run('cmake.configure')
    end
end

function M.conan_install_enabled(ctx)
    local cmake_project = ctx.project_type
    return cmake_project.has_conan and cmake_project.config.selected_profile
end

function M.show_cache_variables(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if not profile then
        return
    end
    return 'cmake -B ' .. profile:get_build_dir() .. ' -L'
end

function M.show_cache_variables_enabled(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if not profile then
        return false
    end
    return profile:is_configured()
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
        for key, profile in pairs(cmake_project.config.profiles) do
            local profileNode = NuiTree.Node({ text = profile:get_name() }, profile:get_info_node())
            if profile == selected then
                profileNode.text = profileNode.text .. ' (current)'
            end
            profileNode.id = key
            table.insert(profileNodes, profileNode)
        end
        table.insert(nodes, NuiTree.Node({ text = 'Profiles:' }, profileNodes))
    else
        table.insert(nodes, 'No profile available')
    end
    return nodes
end

return M
