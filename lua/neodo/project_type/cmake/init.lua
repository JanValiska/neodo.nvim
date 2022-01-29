local M = {}

local picker = require("neodo.picker")
local notify = require("neodo.notify")
local fs = require("neodo.file")
local code_model = require("neodo.project_type.cmake.code_model")
local compilers = require("neodo.compilers")

local cmake_config_file_name = "neodo_cmake_config.json"

local function load_config(project)
	if not project.data_path then
		return
	end
	local config_file = project.data_path .. "/" .. cmake_config_file_name
	fs.file_exists("compile_commands.json")
	local function load_conan()
		project.config.has_conan = fs.file_exists("conanfile.txt")
	end
	fs.read(config_file, 438, function(err, data)
		if err then
			load_conan()
			return
		else
			local config = vim.fn.json_decode(data)
			project.config = config
			for key, profile in pairs(project.config.profiles) do
				if profile.configured then
					project.code_models[key] = code_model:new(profile.build_dir)
				end
			end
			for _, cm in pairs(project.code_models) do
				cm:read_reply()
			end
			load_conan()
		end
	end)
end

local function save_config(project)
	if not project.data_path then
		notify.error("Cannot save config, project config data path not found", "NeoDo > CMake")
		return
	end
	local config_file = project.data_path .. "/" .. cmake_config_file_name
	fs.write(config_file, 444, vim.fn.json_encode(project.config), function()
		notify.info("Configuration saved", "NeoDo > CMake")
	end)
end

local function get_selected_profile(project)
	local profile_key = project.config.selected_profile
	if not profile_key then
		return nil
	end
	return project.config.profiles[profile_key]
end

local function switch_compile_commands(profile)
	if profile.configured then
		if fs.file_exists("compile_commands.json") then
			fs.delete("compile_commands.json")
		end
		fs.symlink(profile.build_dir .. "/compile_commands.json", "compile_commands.json")
	end
end

local function select_profile(profile_key, project)
	project.config.selected_profile = profile_key
	project.config.selected_target = nil
	local profile = project.config.profiles[profile_key]
	switch_compile_commands(profile)
	save_config(project)
end

local function delete_profile(profile_key, project)
	local profile = project.config.profiles[profile_key]
	fs.delete(profile.build_dir)
	project.config.profiles[profile_key] = nil
	project.code_models[profile_key] = nil
	project.config.selected_profile = nil
	save_config(project)
end

local function create_profile(_, project)
	vim.ui.input({ prompt = "Provide new profile name: ", default = "Debug", kind='center'}, function(input)
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
            kind = 'center'
		}, function(params)
			profile.cmake_params = params
			profile.configured = false
			project.config.profiles[profile_key] = profile
			select_profile(profile_key, project)
			project.config.selected_target = nil
			save_config(project)
		end)
	end)
	return { type = "success" }
end

local function configure(_, project)
	local profile = get_selected_profile(project)
	local profile_key = project.config.selected_profile
	project.code_models[profile_key] = code_model:new(profile.build_dir)
	project.code_models[profile_key]:write_query()
	local cmd = ""
	cmd = cmd .. "cmake -B " .. profile.build_dir .. " " .. profile.cmake_params
	return { type = "success", text = cmd }
end

local function get_targets(project)
	local profile_key = project.config.selected_profile
	local cm = project.code_models[profile_key]
	return cm:get_targets()
end

M.register = function()
	local settings = require("neodo.settings")
	settings.project_type.cmake = {
		name = "CMake",
		patterns = { "CMakeLists.txt" },
		on_attach = function(project)
			load_config(project)
		end,
		user_on_attach = nil,
		buffer_on_attach = nil,
		user_buffer_on_attach = nil,
		config = { selected_target = nil, selected_profile = nil, profiles = {} },
		code_models = {},
		commands = {
			create_profile = {
				type = "function",
				name = "CMake > Create profile",
				notify = false,
				cmd = create_profile,
			},
			select_profile = {
				type = "function",
				name = "CMake > Select profile",
				notify = false,
				cmd = function(_, project)
					picker.pick("Select profile: ", vim.tbl_keys(project.config.profiles), function(profile)
						select_profile(profile, project)
					end)
					return { type = "success" }
				end,
				enabled = function(_, project)
					return vim.tbl_count(project.config.profiles) ~= 0
				end,
			},
			delete_profile = {
				type = "function",
				name = "CMake > Delete profile",
				notify = false,
				cmd = function(_, project)
					picker.pick("Select profile to delete: ", vim.tbl_keys(project.config.profiles), function(profile)
						delete_profile(profile, project)
					end)
					return { type = "success" }
				end,
				enabled = function(_, project)
					return vim.tbl_count(project.config.profiles) ~= 0
				end,
			},
			select_target = {
				type = "function",
				name = "CMake > Select target",
				notify = false,
				cmd = function(_, project)
					local targets = get_targets(project)
					picker.pick("Select target: ", vim.tbl_keys(targets), function(selection)
						project.config.selected_target = selection
						save_config(project)
					end)
					return { type = "success" }
				end,
				enabled = function(_, project)
					local profile = get_selected_profile(project)
					if not profile then
						return false
					end
					return profile.configured and vim.tbl_count(get_targets(project)) ~= 0
				end,
			},
			clean = {
				type = "background",
				name = "Clean",
				cmd = function(_, project)
					local profile = project.config.profiles[project.config.selected_profile]
					local cmd = "cmake --build " .. profile.build_dir .. " --target clean"
					return { type = "success", text = cmd }
				end,
				enabled = function(_, project)
					local profile = get_selected_profile(project)
					if not profile then
						return false
					end
					return profile.configured
				end,
			},
			build_all = {
				type = "terminal",
				name = "CMake > Build all",
				cmd = function(_, project)
					local profile = project.config.profiles[project.config.selected_profile]
					local cmd = "cmake --build " .. profile.build_dir
					return { type = "success", text = cmd }
				end,
				enabled = function(_, project)
					local profile = get_selected_profile(project)
					return profile ~= nil and profile.configured
				end,
				errorformat = compilers.get_errorformat("gcc"),
			},
			build_selected_target = {
				type = "terminal",
				name = "CMake > Build selected target",
				cmd = function(_, project)
					if project.config.selected_target == nil then
						return { type = "error", text = "No target selected" }
					end

					local profile = project.config.profiles[project.config.selected_profile]
					local cmd = "cmake --build " .. profile.build_dir .. " --target " .. project.config.selected_target

					return {
						type = "success",
						text = cmd,
					}
				end,
				enabled = function(_, project)
					return project.config.selected_target ~= nil
				end,
				errorformat = compilers.get_errorformat("gcc"),
			},
			run_selected_target = {
				type = "terminal",
				name = "CMake > Run selected target",
				cmd = function(_, _)
					return { type = "error", text = "Not implemented" }
				end,
				enabled = function(_, project)
					return project.config.selected_target ~= nil
				end,
			},
			conan_install = {
				type = "terminal",
				name = "CMake > Install conan packages",
				cmd = function(_, project)
					local profile = project.config.profiles[project.config.selected_profile]
					local cmd = "conan install --build=missing -if " .. profile.build_dir .. " ."
					return { type = "success", text = cmd }
				end,
				enabled = function(_, project)
					return project.config.has_conan and project.config.selected_profile
				end,
			},
			configure = {
				type = "terminal",
				name = "CMake > Configure",
				cmd = configure,
				enabled = function(_, project)
					local function conan_installed()
						local profile = get_selected_profile(project)
						if project.config.has_conan then
							return fs.file_exists(profile.build_dir .. "/conan.lock")
						end
						return true
					end
					return (project.config.selected_profile ~= nil) and conan_installed()
				end,
				on_success = function(project)
					local profile = get_selected_profile(project)
					local profile_key = project.config.selected_profile
					project.code_models[profile_key]:read_reply()
					profile.configured = true
					switch_compile_commands(profile)
					save_config(project)
				end,
			},
		},
		statusline = function(project)
			local statusline = ""
			if project.config.selected_profile then
				statusline = project.config.selected_profile
				local profile = project.config.profiles[project.config.selected_profile]
				if not profile.configured then
					statusline = statusline .. "(⚠ unconfigured)"
				else
					if project.config.selected_target then
						statusline = statusline .. " ❯ " .. project.config.selected_target
					end
				end
			else
				statusline = "(⚠ no profile)"
			end
			return statusline
		end,
	}
end

return M
