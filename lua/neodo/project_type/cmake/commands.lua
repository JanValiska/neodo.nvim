local M = {}

local fs = require("neodo.file")
local picker = require("neodo.picker")
local code_model = require("neodo.project_type.cmake.code_model")
local config = require("neodo.project_type.cmake.config")
local functions = require('neodo.project_type.cmake.functions')

function M.create_profile(_, project)
    picker.pick("Select build type: ", { 'Debug', 'Release', 'RelWithDebInfo', 'MinSizeRel' }, function(build_type)
        local function create_profile(build_configuration)
            local profile_key = build_type
            local profile = {
                name = build_type,
                cmake_params = "-DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DCMAKE_BUILD_TYPE=" .. build_type,
                env_vars = "",
                configured = false,
            }
            if build_configuration then
                profile.cmake_params = profile.cmake_params .. ' ' .. build_configuration.cmake_params
                profile.name = profile.name .. '-' .. build_configuration.name
                profile.env_vars = profile.env_vars .. ' ' .. build_configuration.env_vars
                profile_key = profile_key .. '-' .. string.gsub(build_configuration.name, "%s+", "-")
            end
            profile.build_dir = "build-" .. profile_key
            fs.mkdir(profile.build_dir)
            project.config.profiles[profile_key] = profile
            M.select_profile(profile_key, project)
            project.config.selected_target = nil
            config.save(project)
        end

        if project.config.build_configurations then
            picker.pick("Select build configuration:", vim.tbl_keys(project.config.build_configurations),
                function(bc_key)
                    local build_configuration = project.config.build_configurations[bc_key]
                    create_profile(build_configuration)
                end)
        else
            create_profile(nil)
        end
    end)
end

function M.select_profile(_, project)
    picker.pick("Select profile: ", vim.tbl_keys(project.config.profiles), function(profile_key)
        project.config.selected_profile = profile_key
        project.config.selected_target = nil
        local profile = project.config.profiles[profile_key]
        functions.switch_compile_commands(profile)
        config.save(project)
    end)
end

function M.select_profile_enabled(_, project)
    return vim.tbl_count(project.config.profiles) ~= 0
end

function M.delete_profile(_, project)
    picker.pick("Select profile to delete: ", vim.tbl_keys(project.config.profiles), function(profile_key)
        local profile = project.config.profiles[profile_key]
        fs.delete(profile.build_dir)
        project.config.profiles[profile_key] = nil
        project.code_models[profile_key] = nil
        project.config.selected_profile = nil
        config.save(project)
    end)
end

function M.delete_profile_enabled(_, project)
    return vim.tbl_count(project.config.profiles) ~= 0
end

function M.select_target(_, project)
    local targets = M.get_targets(project)
    picker.pick("Select target: ", vim.tbl_keys(targets), function(selection)
        project.config.selected_target = selection
        config.save(project)
    end)
end

function M.select_target_enabled(_, project)
    local profile = functions.get_selected_profile(project)
    if not profile then
        return false
    end
    return profile.configured and vim.tbl_count(M.get_targets(project)) ~= 0
end

function M.clean(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    return "cmake --build " .. profile.build_dir .. " --target clean"
end

function M.clean_enabled(_, project)
    local profile = functions.get_selected_profile(project)
    if not profile then
        return false
    end
    return profile.configured
end

function M.build_all(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    return "cmake --build " .. profile.build_dir
end

function M.build_all_enabled(_, project)
    local profile = functions.get_selected_profile(project)
    if profile == nil then
        return false
    end
    return profile.configured
end

function M.configure(_, project)
    local profile = functions.get_selected_profile(project)
    local profile_key = project.config.selected_profile
    project.code_models[profile_key] = code_model:new(profile.build_dir)
    project.code_models[profile_key]:write_query()
    return "cmake -B " .. profile.build_dir .. " " .. profile.cmake_params
end

function M.configure_enabled(_, project)
    local function conan_installed()
        local profile = functions.get_selected_profile(project)
        if profile == nil then
            return false
        end
        if project.config.has_conan then
            return fs.file_exists(profile.build_dir .. "/conan.lock")
        end
        return true
    end

    return (project.config.selected_profile ~= nil) and conan_installed()
end

function M.configure_on_success(project)
    local profile = functions.get_selected_profile(project)
    local profile_key = project.config.selected_profile
    project.code_models[profile_key]:read_reply()
    profile.configured = true
    functions.switch_compile_commands(profile)
    config.save(project)
end

function M.build_selected_target(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    return "cmake --build " .. profile.build_dir .. " --target " .. project.config.selected_target
end

function M.build_selected_target_enabled(_, project)
    return project.config.selected_target ~= nil
end

function M.run_selected_target(_, project)
    local target = M.get_targets(project)[project.config.selected_target]
    return target.paths[1]
end

function M.run_selected_target_enabled(_, project)
    return project.config.selected_target ~= nil and
        M.get_targets(project)[project.config.selected_target].type == "EXECUTABLE"
end

function M.conan_install(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    return "conan install --build=missing -if " .. profile.build_dir .. " ."
end

function M.conan_install_enabled(_, project)
    return project.config.has_conan and project.config.selected_profile
end

function M.get_targets(project)
    local profile_key = project.config.selected_profile
    local cm = project.code_models[profile_key]
    return cm:get_targets()
end

return M
