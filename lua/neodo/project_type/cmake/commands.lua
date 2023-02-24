local M = {}

local utils = require('neodo.utils')
local fs = require('neodo.file')
local picker = require('neodo.picker')
local config = require('neodo.project_type.cmake.config')
local functions = require('neodo.project_type.cmake.functions')
local notify = require('neodo.notify')
local Profile = require('neodo.project_type.cmake.profile')
local Path = require('plenary.path')

local function select_build_configuration(cmake_project, callback)
    if type(callback) ~= 'function' then
        return
    end

    local function format_build_configuration(item)
        return cmake_project.build_configurations[item].name
    end

    picker.pick('Select build configuration:', vim.tbl_keys(cmake_project.build_configurations), function(key)
        if not key then
            notify.warning('Build configuration selection canceled.')
            return
        end
        callback(key)
    end, format_build_configuration)
end

local function check_profile_name_already_exists(cmake_project, name)
    for _, profile in pairs(cmake_project.config.profiles) do
        if name == profile:get_name() then
            return true
        end
    end
    return false
end

local function check_profile_with_build_directory_already_exists(cmake_project, directory)
    for _, profile in pairs(cmake_project.config.profiles) do
        if directory == profile:get_build_dir() then
            return true
        end
    end
    return false
end

local function save_and_reconfigure(ctx, profile)
    config.save(ctx.project, ctx.project_type, function()
        if ctx.project_type.has_conan then
            if profile:has_conan_profile() then
                ctx.project:run('cmake.conan_install')
            else
                ctx.project:run('cmake.select_conan_profile')
            end
        elseif ctx.project_type.autoconfigure == true then
            ctx.project:run('cmake.configure')
        end
    end)
end

function M.has_selected_profile(ctx)
    return functions.get_selected_profile(ctx.project_type) ~= nil
end

function M.create_profile(ctx)
    local cmake_project = ctx.project_type

    picker.pick('Select build type: ', { 'Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel' }, function(build_type)
        if cmake_project.build_configurations then
            local create_profile = function(build_configuration_key)
                local function ask_profile_name(name)
                    vim.ui.input({ prompt = 'Profile name', default = name }, function(confirmed_name)
                        if not confirmed_name then
                            notify.warning('Profile name selection canceled.')
                            return
                        end

                        if check_profile_name_already_exists(cmake_project, confirmed_name) then
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

                                if
                                    check_profile_with_build_directory_already_exists(
                                        cmake_project,
                                        confirmed_directory
                                    )
                                then
                                    notify.warning('Profile with same build directory already exists. Try new one.')
                                    ask_build_directory(Path:new(confirmed_directory))
                                    return
                                end

                                local profile = Profile:new(ctx.project, cmake_project)
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
                                save_and_reconfigure(ctx, profile)
                            end)
                        end
                        local suggested_build_directory = Path
                            :new(
                                ctx.project:get_path(),
                                'build-' .. build_type .. '-' .. string.gsub(build_configuration_key, '%s+', '-')
                            )
                            :absolute()
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

            select_build_configuration(cmake_project, create_profile)
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

function M.run_selected_target(inopts)
    local opts = inopts or {}

    local function get_profile(ctx)
        return functions.get_selected_profile(ctx.project_type)
    end

    opts.enabled = opts.enabled
        or function(ctx)
            local profile = get_profile(ctx)
            return profile and profile:has_selected_target() and profile:get_selected_target().type == 'EXECUTABLE'
        end

    opts.cmd = opts.cmd
        or function(ctx)
            local profile = get_profile(ctx)
            return profile and profile:has_selected_target() and profile:get_selected_target().paths[1].filename or nil
        end

    opts.cwd = opts.cwd
        or function(ctx)
            local profile = get_profile(ctx)
            return profile and profile:get_selected_target_cwd() or nil
        end
    return opts
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
            ctx.project:run('cmake.conan_install')
        elseif cmake_project.autoconfigure == true then
            ctx.project:run('cmake.configure')
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
    local cmd = { 'conan', 'install' }
    if profile:has_conan_profile() then
        cmd = utils.tbl_append(cmd, { '--profile', profile:get_conan_profile() })
    end
    return utils.tbl_append(cmd, { '-if', profile:get_build_dir(), '.' })
end

function M.conan_install_on_success(ctx)
    local cmake_project = ctx.project_type
    if cmake_project.autoconfigure == true then
        ctx.project:run('cmake.configure')
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
    return { 'cmake', '-B', profile:get_build_dir(), '-L' }
end

function M.show_cache_variables_enabled(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if not profile then
        return false
    end
    return profile:is_configured()
end

function M.change_build_configuration(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if not profile then
        return false
    end
    select_build_configuration(ctx.project_type, function(build_configuration_key)
        if not build_configuration_key then
            notify.warning('Build configuration change canceled.')
            return
        end

        if build_configuration_key == profile:get_build_configuration() then
            notify.warning('Same build configuration selected. Canceling.')
            return
        end

        profile:set_build_configuration(build_configuration_key)
        notify.info(
            "Build configuration changed to '"
                .. ctx.project_type.build_configurations[build_configuration_key].name
                .. "'"
        )
        save_and_reconfigure(ctx, profile)
    end)
end

function M.rename_profile(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if not profile then
        return false
    end
    local function ask_profile_name(name)
        vim.ui.input({ prompt = 'New profile name', default = name }, function(new_name)
            if not new_name then
                notify.warning('Profile name change canceled.')
                return
            end

            if new_name == profile:get_name() then
                notify.warning('Same profile name entered. Skipping rename.')
                return
            end

            if check_profile_name_already_exists(ctx.project_type, new_name) then
                notify.warning('Profile with same name already exists. Try new one.')
                ask_profile_name(new_name)
                return
            end

            profile:set_name(new_name)
            notify.info("Profile name changed to '" .. new_name .. "'")
            config.save(ctx.project, ctx.project_type)
        end)
    end
    ask_profile_name(profile:get_name())
end

function M.change_build_directory(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if not profile then
        return false
    end
    local function ask_dir_name(name)
        vim.ui.input({ prompt = 'New build directory', default = name }, function(new_build_directory)
            if not new_build_directory then
                notify.warning('Build directory selection canceled.')
                return
            end

            if new_build_directory == profile:get_build_dir() then
                notify.info('Keeping old build directory.')
                return
            end

            if check_profile_with_build_directory_already_exists(ctx.project_type, new_build_directory) then
                notify.warning('Profile with same build directory already exists. Try new one.')
                ask_dir_name(new_build_directory)
                return
            end

            vim.ui.input({ prompt = 'Keep old build directory? y/n', default = 'y' }, function(answer)
                if answer == 'n' or answer == 'N' then
                    fs.delete(profile:get_build_dir())
                end
                profile:set_build_dir(new_build_directory)
                notify.info("Build directory changed to '" .. new_build_directory .. "'")
                save_and_reconfigure(ctx, profile)
            end)
        end)
    end
    ask_dir_name(profile:get_build_dir())
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
