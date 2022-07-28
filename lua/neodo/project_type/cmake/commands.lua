local M = {}

local fs = require("neodo.file")
local picker = require("neodo.picker")
local code_model = require("neodo.project_type.cmake.code_model")
local config = require("neodo.project_type.cmake.config")

function M.get_selected_profile(project)
    local profile_key = project.config.selected_profile
    if not profile_key then
        return nil
    end
    return project.config.profiles[profile_key]
end

function M.switch_compile_commands(profile)
    if profile.configured then
        if fs.file_exists("compile_commands.json") then
            fs.delete("compile_commands.json")
        end
        fs.symlink(profile.build_dir .. "/compile_commands.json", "compile_commands.json")
    end
end

function M.create_profile(_, project)
    vim.ui.input({ prompt = "Provide new profile name: ", default = "Debug", kind = 'neodo.input.center' },
        function(input)
            local profile = {}
            profile.name = input
            if not profile.name then
                return
            end
            local profile_key = string.gsub(profile.name, "%s+", "-")
            profile.build_dir = "build-" .. profile_key
            fs.mkdir(profile.build_dir)
            vim.ui.input({
                prompt = "Provide CMake params: ",
                default = "-DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DCMAKE_BUILD_TYPE=Debug",
                kind = 'neodo.input.center'
            }, function(params)
                profile.cmake_params = params
                profile.configured = false
                project.config.profiles[profile_key] = profile
                M.select_profile(profile_key, project)
                project.config.selected_target = nil
                config.save(project)
            end)
        end)
    return { type = "success" }
end

function M.select_profile(_, project)
    picker.pick("Select profile: ", vim.tbl_keys(project.config.profiles), function(profile_key)
        project.config.selected_profile = profile_key
        project.config.selected_target = nil
        local profile = project.config.profiles[profile_key]
        M.switch_compile_commands(profile)
        config.save(project)
    end)
    return { type = "success" }
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
    return { type = "success" }
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
    return { type = "success" }
end

function M.select_target_enabled(_, project)
    local profile = M.get_selected_profile(project)
    if not profile then
        return false
    end
    return profile.configured and vim.tbl_count(M.get_targets(project)) ~= 0
end

function M.clean(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    local cmd = "cmake --build " .. profile.build_dir .. " --target clean"
    return { type = "success", text = cmd }
end

function M.clean_enabled(_, project)
    local profile = M.get_selected_profile(project)
    if not profile then
        return false
    end
    return profile.configured
end

function M.build_all(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    local cmd = "cmake --build " .. profile.build_dir
    return { type = "success", text = cmd }
end

function M.build_all_enabled(_, project)
    local profile = M.get_selected_profile(project)
    if profile == nil then
        return false
    end
    return profile.configured
end

function M.configure(_, project)
    local profile = M.get_selected_profile(project)
    if profile == nil then
        return { type = "error", text = "Cannot find profile" }
    end
    local profile_key = project.config.selected_profile
    project.code_models[profile_key] = code_model:new(profile.build_dir)
    project.code_models[profile_key]:write_query()
    local cmd = ""
    cmd = cmd .. "cmake -B " .. profile.build_dir .. " " .. profile.cmake_params
    return { type = "success", text = cmd }
end

function M.configure_enabled(_, project)
    local function conan_installed()
        local profile = M.get_selected_profile(project)
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
    local profile = M.get_selected_profile(project)
    local profile_key = project.config.selected_profile
    project.code_models[profile_key]:read_reply()
    profile.configured = true
    M.switch_compile_commands(profile)
    config.save(project)
end

function M.build_selected_target(_, project)
    if project.config.selected_target == nil then
        return { type = "error", text = "No target selected" }
    end

    local profile = project.config.profiles[project.config.selected_profile]
    local cmd = "cmake --build " .. profile.build_dir .. " --target " .. project.config.selected_target

    return {
        type = "success",
        text = cmd,
    }
end

function M.build_selected_target_enabled(_, project)
    return project.config.selected_target ~= nil
end

function M.run_selected_target(_, project)
    local target = M.get_targets(project)[project.config.selected_target]
    return { type = "success", text = target.paths[1] }
end

function M.run_selected_target_enabled(_, project)
    return project.config.selected_target ~= nil and
        M.get_targets(project)[project.config.selected_target].type == "EXECUTABLE"
end

function M.conan_install(_, project)
    local profile = project.config.profiles[project.config.selected_profile]
    local cmd = "conan install --build=missing -if " .. profile.build_dir .. " ."
    return { type = "success", text = cmd }
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
