local M = {}

local utils = require('neodo.utils')
local fs = require('neodo.file')
local picker = require('neodo.picker')
local compilers = require('neodo.compilers')
local config = require('neodo.project_type.cmake.config')
local functions = require('neodo.project_type.cmake.functions')
local notify = require('neodo.notify')
local Profile = require('neodo.project_type.cmake.profile')
local Path = require('plenary.path')

local function select_build_configuration(cmake_project, callback)
    if type(callback) ~= 'function' then return end

    local function format_build_configuration(item)
        return cmake_project.build_configurations[item].name
    end

    picker.pick(
        'Select build configuration:',
        vim.tbl_keys(cmake_project.build_configurations),
        function(key)
            if not key then
                notify.warning('Build configuration selection canceled.')
                return
            end
            callback(key)
        end,
        format_build_configuration
    )
end

local function select_profile(cmake_project, callback)
    if type(callback) ~= 'function' then return end
    local function format_names(profile_key)
        return cmake_project.config.profiles[profile_key]:get_name()
    end
    picker.pick(
        'Select profile:',
        vim.tbl_keys(cmake_project.config.profiles),
        function(profile_key)
            if not profile_key then
                notify.warning('Profile selection canceled.')
                return
            end
            callback(profile_key)
        end,
        format_names
    )
end

local function confirm(callback, opts)
    if type(callback) ~= 'function' then return end
    opts = opts or {}
    opts.default = opts.default or 'n'
    opts.prompt = opts.prompt or 'Really?'
    opts.prompt = opts.prompt .. ' y/n'
    vim.ui.input(opts, function(answer)
        if answer == 'n' or answer == 'N' then
            callback(false)
        else
            callback(true)
        end
    end)
end

local function check_profile_name_already_exists(cmake_project, name)
    for _, profile in pairs(cmake_project.config.profiles) do
        if name == profile:get_name() then return true end
    end
    return false
end

local function check_profile_with_build_directory_already_exists(cmake_project, directory)
    for _, profile in pairs(cmake_project.config.profiles) do
        if directory == profile:get_build_dir() then return true end
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

function M.get_selected_profile(ctx) return functions.get_selected_profile(ctx.project_type) end

function M.has_selected_profile(ctx) return functions.get_selected_profile(ctx.project_type) ~= nil end

local function create_profile(ctx)
    local cmake_project = ctx.project_type

    picker.pick(
        'Select build type: ',
        { 'Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel' },
        function(build_type)
            if cmake_project.build_configurations then
                local create_profile_impl = function(build_configuration_key)
                    local function ask_profile_name(name)
                        vim.ui.input(
                            { prompt = 'Profile name', default = name },
                            function(confirmed_name)
                                if not confirmed_name then
                                    notify.warning('Profile name selection canceled.')
                                    return
                                end

                                if
                                    check_profile_name_already_exists(cmake_project, confirmed_name)
                                then
                                    notify.warning(
                                        'Profile with same name already exists. Try new one.'
                                    )
                                    ask_profile_name(confirmed_name)
                                    return
                                end

                                local function ask_build_directory(build_directory)
                                    vim.ui.input({
                                        prompt = 'Build directory',
                                        default = build_directory,
                                    }, function(
                                        confirmed_directory
                                    )
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
                                            notify.warning(
                                                'Profile with same build directory already exists. Try new one.'
                                            )
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
                                        notify.info(
                                            "New profile '"
                                                .. profile:get_name()
                                                .. "' selected as active"
                                        )
                                        save_and_reconfigure(ctx, profile)
                                    end)
                                end
                                local suggested_build_directory = Path
                                    :new(
                                        ctx.project:get_path(),
                                        'build-'
                                            .. build_type
                                            .. '-'
                                            .. string.gsub(build_configuration_key, '%s+', '-')
                                    )
                                    :absolute()
                                ask_build_directory(suggested_build_directory)
                            end
                        )
                    end
                    local suggested_name = build_type
                        .. '-'
                        .. cmake_project.build_configurations[build_configuration_key].name
                    ask_profile_name(suggested_name)
                end

                -- in case that there is only one build configuration
                if vim.tbl_count(cmake_project.build_configurations) == 1 then
                    for key, _ in pairs(cmake_project.build_configurations) do
                        create_profile_impl(key)
                        return
                    end
                end

                select_build_configuration(cmake_project, create_profile_impl)
            else
                notify.error('No build configurations found. Check config/instalation.')
            end
        end
    )
end

function M.create_profile(opts)
    opts = opts or {}

    opts.name = opts.name or 'Create profile'
    opts.notify = opts.notify or false

    opts.fn = opts.fn or function(ctx) create_profile(ctx) end
    return opts
end

function M.select_profile(opts)
    opts = opts or {}
    opts.name = opts.name or 'Select profile'
    opts.enabled = opts.enabled
        or function(ctx) return vim.tbl_count(ctx.project_type.config.profiles) ~= 0 end
    opts.fn = opts.fn
        or function(ctx)
            local cmake_project = ctx.project_type
            select_profile(cmake_project, function(profile_key)
                cmake_project.config.selected_profile = profile_key
                local profile = cmake_project.config.profiles[profile_key]
                functions.switch_compile_commands(profile)
                config.save(ctx.project, cmake_project)
            end)
        end
    return opts
end

function M.delete_profile(opts)
    opts = opts or {}
    opts.name = opts.name or 'Delete profile'
    opts.notify = opts.notify or false
    opts.enabled = opts.enabled
        or function(ctx) return vim.tbl_count(ctx.project_type.config.profiles) ~= 0 end
    opts.fn = opts.fn
        or function(ctx)
            local cmake_project = ctx.project_type
            select_profile(cmake_project, function(profile_key)
                local profile = cmake_project.config.profiles[profile_key]
                confirm(function(really_delete)
                    if really_delete then
                        confirm(function(keep_build_dir)
                            if not keep_build_dir then fs.delete(profile:get_build_dir()) end
                            cmake_project.config.profiles[profile_key] = nil
                            if profile_key == cmake_project.config.selected_profile then
                                cmake_project.config.selected_profile = nil
                            end
                            config.save(ctx.project, cmake_project)
                        end, {
                            prompt = 'Keep build directory?',
                            default = 'y',
                        })
                    end
                end, {
                    prompt = 'Really DELETE profile: ' .. profile:get_name() .. '?',
                    default = 'n',
                })
            end)
        end
    return opts
end

function M.configure(opts)
    opts = opts or {}
    opts.name = opts.name or 'Configure'
    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:conan_installed()
        end
    opts.cmd = opts.cmd
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:get_configure_command() or nil
        end

    opts.on_success = opts.on_success
        or function(ctx)
            local cmake_project = ctx.project_type
            local profile = functions.get_selected_profile(cmake_project)
            if not profile then return end
            profile:set_configured()
            functions.switch_compile_commands(profile)
            config.save(ctx.project, cmake_project)
        end
    return opts
end

function M.select_target(opts)
    opts = opts or {}
    opts.name = opts.name or 'Select target'
    opts.notify = opts.notify or false
    opts.fn = opts.fn
        or function(ctx)
            local cmake_project = ctx.project_type
            local profile = M.get_selected_profile(ctx)
            if not profile then return end
            local targets = profile and profile:get_targets()
            local function format_names(target_key)
                local target = targets[target_key]
                return target.name .. ' (' .. target.type .. ')'
            end
            picker.pick('Select target: ', vim.tbl_keys(profile:get_targets()), function(target)
                profile:select_target(target)
                config.save(ctx.project, cmake_project)
            end, format_names)
        end
    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:is_configured() and vim.tbl_count(profile:get_targets()) ~= 0
        end
    return opts
end

function M.build_all(opts)
    opts = opts or {}
    opts.name = opts.name or 'Build all'
    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:is_configured()
        end
    opts.cmd = opts.cmd
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:get_build_all_command() or nil
        end
    opts.errorformat = compilers.get_errorformat('gcc')
    return opts
end

function M.build_selected_target(opts)
    opts = opts or {}

    opts.name = opts.name or 'Build selected target'

    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:has_selected_target()
        end

    opts.cmd = opts.cmd
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:get_build_selected_target_command() or nil
        end

    opts.errorformat = compilers.get_errorformat('gcc')
    return opts
end

function M.clean(opts)
    opts = opts or {}
    opts.name = opts.name or 'Clean'
    opts.notify = opts.notify or false
    opts.cmd = opts.cmd
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:get_clean_command()
        end
    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:is_configured()
        end
    return opts
end

function M.run_selected_target(opts)
    opts = opts or {}

    opts.name = opts.name or 'Run selected target'

    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile
                and profile:has_selected_target()
                and profile:get_selected_target().type == 'EXECUTABLE'
        end

    opts.cmd = opts.cmd
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile
                    and profile:has_selected_target()
                    and profile:get_selected_target().paths[1].filename
                or nil
        end

    opts.cwd = opts.cwd
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:get_selected_target_cwd() or nil
        end
    return opts
end

function M.debug_selected_target(opts)
    opts = opts or {}

    opts.name = opts.name or 'Debug selected target'

    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile
                and profile:has_selected_target()
                and profile:get_selected_target().type == 'EXECUTABLE'
                and profile:get_selected_target().paths[1]:exists()
                and profile:get_debugging_adapter()
        end

    opts.fn = opts.dn
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            if not profile then return end

            local cwd = profile and profile:get_selected_target_cwd() or nil
            if not cwd then return end
            local executable = profile
                    and profile:has_selected_target()
                    and profile:get_selected_target().paths[1].filename
                or nil
            if not executable then return end

            local adapter = profile:get_debugging_adapter()
            if not adapter then return end

            local dap = require('dap')
            local configuration = {
                args = {},
                cwd = cwd,
                program = executable,
                request = 'launch',
                stopOnEntry = false,
                type = adapter,
            }
            dap.run(configuration)
        end
    return opts
end

function M.conan_install(opts)
    opts = opts or {}

    opts.name = opts.name or 'Conan install packages'

    opts.enabled = opts.enabled
        or function(ctx) return ctx.project_type.has_conan and M.get_selected_profile(ctx) end

    opts.cmd = opts.cmd
        or function(ctx)
            local cmake_project = ctx.project_type
            local profile = functions.get_selected_profile(cmake_project)
            if not profile then return end
            local cmd = { 'conan', 'install' }
            if profile:has_conan_profile() then
                cmd = utils.tbl_append(cmd, { '--profile', profile:get_conan_profile() })
            end
            return utils.tbl_append(cmd, { '-if', profile:get_build_dir(), '.' })
        end

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
            picker.pick(
                'Select conan profile: ',
                utils.get_output('conan profile list'),
                function(conan_profile)
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
                end
            )
        end

    return opts
end

function M.show_cache_variables(opts)
    opts = opts or {}
    opts.name = opts.name or 'Show cache variables'
    opts.keep_terminal_open = opts.keep_terminal_open or true
    opts.cmd = opts.cmd
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and { 'cmake', '-B', profile:get_build_dir(), '-L' }
        end
    opts.enabled = opts.enabled
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            return profile and profile:is_configured()
        end
    return opts
end

function M.change_build_configuration(opts)
    opts = opts or {}
    opts.name = opts.name or 'Change build configuration'
    opts.fn = opts.fn
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            if not profile then return false end
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
    opts.enabled = opts.enabled or function(ctx) return M.get_selected_profile(ctx) ~= nil end
    return opts
end

function M.rename_profile(opts)
    opts = opts or {}
    opts.name = opts.name or 'Rename selected profile'
    opts.fn = opts.fn
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            if not profile then return false end
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
    opts.enabled = opts.enabled or function(ctx) return M.get_selected_profile(ctx) ~= nil end
    return opts
end

function M.change_build_directory(opts)
    opts = opts or {}
    opts.name = opts.name or 'Change build directory'
    opts.fn = opts.fn
        or function(ctx)
            local profile = M.get_selected_profile(ctx)
            if not profile then return false end
            local function ask_dir_name(name)
                vim.ui.input(
                    { prompt = 'New build directory', default = name },
                    function(new_build_directory)
                        if not new_build_directory then
                            notify.warning('Build directory selection canceled.')
                            return
                        end

                        if new_build_directory == profile:get_build_dir() then
                            notify.info('Keeping old build directory.')
                            return
                        end

                        if
                            check_profile_with_build_directory_already_exists(
                                ctx.project_type,
                                new_build_directory
                            )
                        then
                            notify.warning(
                                'Profile with same build directory already exists. Try new one.'
                            )
                            ask_dir_name(new_build_directory)
                            return
                        end

                        confirm(function(keep_old_build_directory)
                            if not keep_old_build_directory then
                                fs.delete(profile:get_build_dir())
                            end
                            profile:set_build_dir(new_build_directory)
                            notify.info(
                                "Build directory changed to '" .. new_build_directory .. "'"
                            )
                            save_and_reconfigure(ctx, profile)
                        end, {
                            prompt = 'Keep old build directory?',
                            default = 'y',
                        })
                    end
                )
            end
            ask_dir_name(profile:get_build_dir())
        end
    opts.enabled = opts.enabled or function(ctx) return M.get_selected_profile(ctx) ~= nil end
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
        for key, profile in pairs(cmake_project.config.profiles) do
            local profileNode = NuiTree.Node({ text = profile:get_name() }, profile:get_info_node())
            if profile == selected then profileNode.text = profileNode.text .. ' (current)' end
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
