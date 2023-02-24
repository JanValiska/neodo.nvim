local uuid = require('neodo.uuid')
local CodeModel = require('neodo.project_type.cmake.code_model')
local Path = require('plenary.path')

local Profile = {}

local function create_build_dir(self)
    if not self.build_directory:is_dir() and not self.build_directory:exists() then
        self.build_directory:mkdir({ parents = true })
    end
end

local function create_code_model(self)
    self.code_model = CodeModel:new(self:get_build_dir())
    self.code_model:write_query()
end

local function get_build_args(props)
    if not props.build_configuration or not props.build_configuration.build_args then
        return ''
    end
    return ' -- ' .. props.build_configuration.build_args
end

local function to_absolute(p)
    return Path:new(Path:new(p):absolute())
end

function Profile:new(project, cmake_project)
    local properties = {
        name = nil,
        default_cmake_options = '-DCMAKE_EXPORT_COMPILE_COMMANDS=1',
        project = project,
        cmake_project = cmake_project,
        configured = false,
        code_model = nil,
    }
    setmetatable(properties, self)
    self.__index = self
    return properties
end

function Profile:load_default(name, build_directory, build_type, build_configuration_key)
    self.key = uuid()
    self.build_type = build_type
    self.build_configuration_key = build_configuration_key
    self.build_configuration = self.cmake_project.build_configurations[self.build_configuration_key]
    self.build_directory = to_absolute(build_directory)
    self.name = name
    create_build_dir(self)
    create_code_model(self)
end

function Profile:load_from_table(table)
    self.build_directory = to_absolute(table.build_directory)
    create_build_dir(self)
    create_code_model(self)
    self.key = table.key
    self.build_type = table.build_type
    self.build_configuration_key = table.build_configuration_key
    self.build_configuration = self.cmake_project.build_configurations[self.build_configuration_key]
    self.name = table.name
    self.conan_profile = table.conan_profile
    self.selected_target = table.selected_target
    self:set_configured()
end

function Profile:save_to_table()
    return {
        key = self.key,
        cmake_options = self.cmake_options,
        build_type = self.build_type,
        build_configuration_key = self.build_configuration_key,
        build_directory = self:get_build_dir(),
        name = self.name,
        selected_target = self.selected_target,
        conan_profile = self.conan_profile,
    }
end

function Profile:get_key()
    return self.key
end

function Profile:is_configured()
    return self.configured
end

function Profile:set_configured()
    local function done(result)
        self.configured = result
    end
    self.code_model:read_reply(done)
end

function Profile:get_build_configuration()
    return self.build_configuration_key
end

function Profile:set_build_configuration(build_configuration_key)
    if self.cmake_project.build_configurations and self.cmake_project.build_configurations[build_configuration_key] then
        self.build_configuration_key = build_configuration_key
        self.build_configuration = self.cmake_project.build_configurations[self.build_configuration_key]
    end
    self.configured = false
end

function Profile:get_name()
    return self.name or 'Unnamed profile'
end

function Profile:set_name(name)
    self.name = name
end

function Profile:get_build_dir()
    return self.build_directory.filename
end

function Profile:set_build_dir(dir)
    self.build_directory = Path:new({ dir })
    self.configured = false
    create_build_dir(self)
    create_code_model(self)
end

function Profile:get_selected_target_cwd()
    local strategy = self.cmake_project.run_cwd_strategy or 'executable_dir'
    if strategy == 'project_dir' then
        return self.project:get_path()
    elseif strategy == 'executable_dir' then
        local target = self:get_selected_target()
        return target and target.paths[1]:parent().filename or self:get_build_dir()
    else
        return self:get_build_dir()
    end
end

function Profile:get_configure_command()
    local args = self.default_cmake_options .. ' -DCMAKE_BUILD_TYPE=' .. self.build_type
    if self.build_configuration and self.build_configuration.cmake_options then
        args = args .. ' ' .. self.build_configuration.cmake_options
    end
    return 'cmake -B ' .. self:get_build_dir() .. ' ' .. args
end

function Profile:get_build_all_command()
    return 'cmake --build ' .. self:get_build_dir() .. get_build_args(self)
end

function Profile:get_clean_command()
    return 'cmake --build ' .. self:get_build_dir() .. ' --target clean'
end

function Profile:get_targets()
    if not self.configured then
        return nil
    end
    return self.code_model:get_targets()
end

function Profile:select_target(target)
    local targets = self:get_targets()
    if not targets then
        return false
    end
    for key, _ in pairs(targets) do
        if key == target then
            self.selected_target = target
            return true
        end
    end
    return false
end

function Profile:get_selected_target()
    local targets = self:get_targets()
    return targets and self.selected_target and targets[self.selected_target] or nil
end

function Profile:has_selected_target()
    return self.selected_target ~= nil
end

function Profile:get_build_selected_target_command()
    if not self.selected_target then
        return nil
    end
    return 'cmake --build ' .. self:get_build_dir() .. ' --target ' .. self.selected_target .. get_build_args(self)
end

function Profile:set_conan_profile(profile)
    self.conan_profile = profile
end

function Profile:get_conan_profile()
    if self.conan_profile then
        return self.conan_profile
    elseif self.build_configuration.conan_profile then
        return self.build_configuration.conan_profile
    end
    return nil
end

function Profile:has_conan_profile()
    return (self.build_configuration and self.build_configuration.conan_profile ~= nil) or self.conan_profile ~= nil
end

function Profile:get_info_node()
    local NuiTree = require('nui.tree')
    local function get_targets_info()
        local targets = self:get_targets()
        if not targets or vim.tbl_count(targets) == 0 then
            return NuiTree.Node({ text = 'No targets defined' })
        end

        local targetNodes = {}
        for _, target in pairs(targets) do
            table.insert(targetNodes, NuiTree.Node({ text = target.name .. '(' .. target.type .. ')' }))
        end
        return NuiTree.Node({ text = 'Targets:' }, targetNodes)
    end
    return {
        NuiTree.Node({ text = 'UUID: ' .. self.key }),
        NuiTree.Node({ text = 'Build directory: ' .. self:get_build_dir() }),
        NuiTree.Node({
            text = 'Build configuration: '
                .. ((self.build_configuration and self.build_configuration.name) or 'MISSING'),
        }),
        NuiTree.Node({ text = 'Build type: ' .. self.build_type }),
        NuiTree.Node({
            text = 'Configured: ' .. (self:is_configured() and 'Yes' or 'No'),
        }),
        NuiTree.Node({
            text = 'Conan profile: ' .. (self:has_conan_profile() and self:get_conan_profile() or 'no profile'),
        }),
        get_targets_info(),
    }
end

return Profile
