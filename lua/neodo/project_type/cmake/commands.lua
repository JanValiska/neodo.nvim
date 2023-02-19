local M = {}

local utils = require('neodo.utils')
local fs = require('neodo.file')
local picker = require('neodo.picker')
local code_model = require('neodo.project_type.cmake.code_model')
local config = require('neodo.project_type.cmake.config')
local functions = require('neodo.project_type.cmake.functions')

function M.create_profile(ctx)
    local cmake_project = ctx.project_type
    picker.pick('Select build type: ', { 'Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel' }, function(build_type)
        local function create_profile(build_configuration)
            local profile_key = build_type
            local profile = {
                name = build_type,
                cmake_params = '-DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DCMAKE_BUILD_TYPE=' .. build_type,
                env_vars = '',
                configured = false,
            }
            if build_configuration then
                profile.cmake_params = profile.cmake_params .. ' ' .. build_configuration.cmake_params
                profile.name = profile.name .. '-' .. build_configuration.name
                profile.env_vars = profile.env_vars .. ' ' .. build_configuration.env_vars
                profile_key = profile_key .. '-' .. string.gsub(build_configuration.name, '%s+', '-')
            end
            profile.build_dir = 'build-' .. profile_key
            fs.mkdir(profile.build_dir)
            cmake_project.config.profiles[profile_key] = profile
            M.select_profile(ctx)
            cmake_project.config.selected_target = nil
            config.save(ctx.project, cmake_project)
        end

        if cmake_project.config.build_configurations then
            picker.pick(
                'Select build configuration:',
                vim.tbl_keys(cmake_project.config.build_configurations),
                function(bc_key)
                    local build_configuration = cmake_project.config.build_configurations[bc_key]
                    create_profile(build_configuration)
                end
            )
        else
            create_profile(nil)
        end
    end)
end

function M.select_profile(ctx)
    local cmake_project = ctx.project_type
    picker.pick('Select profile: ', vim.tbl_keys(cmake_project.config.profiles), function(profile_key)
        cmake_project.config.selected_profile = profile_key
        cmake_project.config.selected_target = nil
        local profile = cmake_project.config.profiles[profile_key]
        functions.switch_compile_commands(profile)
        config.save(ctx.project, cmake_project)
    end)
end

function M.select_profile_enabled(ctx)
    return vim.tbl_count(ctx.project_type.config.profiles) ~= 0
end

function M.delete_profile(ctx)
    local cmake_project = ctx.project_type
    picker.pick('Select profile to delete: ', vim.tbl_keys(cmake_project.config.profiles), function(profile_key)
        local profile = cmake_project.config.profiles[profile_key]
        fs.delete(profile.build_dir)
        cmake_project.config.profiles[profile_key] = nil
        cmake_project.code_models[profile_key] = nil
        cmake_project.config.selected_profile = nil
        config.save(ctx.project, cmake_project)
    end)
end

function M.delete_profile_enabled(ctx)
    return vim.tbl_count(ctx.project_type.config.profiles) ~= 0
end

function M.select_target(ctx)
    local cmake_project = ctx.project_type
    local targets = M.get_targets(cmake_project)
    picker.pick('Select target: ', vim.tbl_keys(targets), function(selection)
        cmake_project.config.selected_target = selection
        config.save(ctx.project, cmake_project)
    end)
end

function M.select_target_enabled(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return false
    end
    return profile.configured and vim.tbl_count(M.get_targets(cmake_project)) ~= 0
end

function M.clean(ctx)
    local cmake_project = ctx.project_type
    local profile = cmake_project.config.profiles[cmake_project.config.selected_profile]
    return 'cmake --build ' .. profile.build_dir .. ' --target clean'
end

function M.clean_enabled(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    if not profile then
        return false
    end
    return profile.configured
end

function M.build_all(ctx)
    local cmake_project = ctx.project_type
    local profile = cmake_project.config.profiles[cmake_project.config.selected_profile]
    return 'cmake --build ' .. profile.build_dir
end

function M.build_all_enabled(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if profile == nil then
        return false
    end
    return profile.configured
end

function M.configure(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    local profile_key = cmake_project.config.selected_profile
    cmake_project.code_models[profile_key] = code_model:new(profile.build_dir)
    cmake_project.code_models[profile_key]:write_query()
    return 'cmake -B ' .. profile.build_dir .. ' ' .. profile.cmake_params
end

function M.configure_enabled(ctx)
    local cmake_project = ctx.project_type
    local function conan_installed()
        local profile = functions.get_selected_profile(cmake_project)
        if profile == nil then
            return false
        end
        if cmake_project.config.has_conan then
            return fs.file_exists(profile.build_dir .. '/conan.lock')
        end
        return true
    end

    return (cmake_project.config.selected_profile ~= nil) and conan_installed()
end

function M.configure_on_success(ctx)
    local cmake_project = ctx.project_type
    local profile = functions.get_selected_profile(cmake_project)
    local profile_key = cmake_project.config.selected_profile
    cmake_project.code_models[profile_key]:read_reply()
    profile.configured = true
    functions.switch_compile_commands(profile)
    config.save(ctx.project, cmake_project)
end

function M.build_selected_target(ctx)
    local cmake_project = ctx.project_type
    local profile = cmake_project.config.profiles[cmake_project.config.selected_profile]
    return 'cmake --build ' .. profile.build_dir .. ' --target ' .. cmake_project.config.selected_target
end

function M.build_selected_target_enabled(ctx)
    return ctx.project_type.config.selected_target ~= nil
end

function M.run_selected_target(ctx)
    local cmake_project = ctx.project_type
    local target = M.get_targets(cmake_project)[cmake_project.config.selected_target]
    return target.paths[1]
end

function M.run_selected_target_enabled(ctx)
    local cmake_project = ctx.project_type
    return cmake_project.config.selected_target ~= nil
        and M.get_targets(cmake_project)[cmake_project.config.selected_target].type == 'EXECUTABLE'
end

function M.select_conan_profile(ctx)
    local cmake_project = ctx.project_type
    picker.pick('Select conan profile: ', utils.get_output('conan profile list'), function(profile)
        local cmake_profile = functions.get_selected_profile(cmake_project)
        cmake_profile.conan_profile = profile
        config.save(ctx.project, cmake_project)
    end)
end

function M.select_conan_profile_enabled(ctx)
    local cmake_project = ctx.project_type
    return cmake_project.config.has_conan and cmake_project.config.selected_profile
end

function M.conan_install(ctx)
    local cmake_project = ctx.project_type
    local cmake_profile = functions.get_selected_profile(cmake_project)
    if not cmake_profile then
        return
    end
    local profile_string = ''
    if cmake_profile.conan_profile then
        profile_string = '--profile ' .. cmake_profile.conan_profile
    end
    return 'conan install ' .. profile_string .. ' -if ' .. cmake_profile.build_dir .. ' .'
end

function M.conan_install_enabled(ctx)
    local cmake_project = ctx.project_type
    return cmake_project.config.has_conan and cmake_project.config.selected_profile
end

function M.show_cache_variables(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    return 'cmake -B ' .. profile.build_dir .. ' -L'
end

function M.show_cache_variables_enabled(ctx)
    local profile = functions.get_selected_profile(ctx.project_type)
    if not profile then
        return false
    end
    return profile.configured
end

function M.get_targets(project)
    local profile_key = project.config.selected_profile
    local cm = project.code_models[profile_key]
    return cm:get_targets()
end

return M
