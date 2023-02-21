local fs = require('neodo.file')
local uuid = require('neodo.uuid')
local CodeModel = require('neodo.project_type.cmake.code_model')

local Profile = {}

local function create_build_dir(self)
    if not fs.dir_exists(self.build_directory) then
        fs.mkdir(self.build_directory)
    end
end

local function create_code_model(self)
    self.code_model = CodeModel:new(self.build_directory)
    self.code_model:write_query()
end

local function get_build_args(props)
    if props.build_configuration.build_args then
        return ' -- ' .. props.build_configuration.build_args
    end
    return ''
end

function Profile:new(project)
    local properties = {
        name = nil,
        default_cmake_options = '-DCMAKE_EXPORT_COMPILE_COMMANDS=1',
        project = project,
        configured = false,
        code_model = nil,
    }
    setmetatable(properties, self)
    self.__index = self
    return properties
end

function Profile:load_default(build_type, build_configuration_key)
    self.key = uuid()
    self.build_type = build_type
    self.build_configuration_key = build_configuration_key
    self.build_configuration = self.project.build_configurations[self.build_configuration_key]
    self.build_directory = 'build-' .. build_type .. '-' .. string.gsub(self.build_configuration.name, '%s+', '-')
    create_build_dir(self)
    create_code_model(self)
end

function Profile:load_from_table(table)
    self.build_directory = table.build_directory
    create_build_dir(self)
    create_code_model(self)
    self.key = table.key
    self.build_type = table.build_type
    self.build_configuration_key = table.build_configuration_key
    self.build_configuration = self.project.build_configurations[self.build_configuration_key]
    self.name = table.name
    self:set_conan_profile(table.conan_profile)
    self:select_target(table.selected_target)
    self:set_configured()
end

function Profile:save_to_table()
    local table = {
        key = self.key,
        cmake_options = self.cmake_options,
        build_type = self.build_type,
        build_configuration_key = self.build_configuration_key,
        build_directory = self.build_directory,
        name = self.name,
        selected_target = self.selected_target,
        conan_profile = self.conan_profile,
    }
    return table
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

function Profile:get_name()
    if self.name then
        return self.name
    end
    return self.build_type .. '-' .. self.build_configuration.name
end

function Profile:set_name(name)
    self.name = name
end

function Profile:get_build_dir()
    return self.build_directory
end

function Profile:set_build_dir(dir)
    self.build_directory = dir
    create_build_dir(self)
    create_code_model(self)
    self.configured = false
end

function Profile:get_configure_command()
    local args = self.default_cmake_options .. ' -DCMAKE_BUILD_TYPE=' .. self.build_type
    if self.build_configuration.cmake_options then
        args = args .. ' ' .. self.build_configuration.cmake_options
    end
    return 'cmake -B ' .. self.build_directory .. ' ' .. args
end

function Profile:get_build_all_command()
    return 'cmake --build ' .. self.build_directory .. get_build_args(self)
end

function Profile:get_clean_command()
    return 'cmake --build ' .. self.build_directory .. ' --target clean'
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
    return self:get_targets()[self.selected_target]
end

function Profile:has_selected_target()
    return self.selected_target ~= nil
end

function Profile:get_build_selected_target_command()
    if not self.selected_target then
        return nil
    end
    return 'cmake --build ' .. self.build_directory .. ' --target ' .. self.selected_target .. get_build_args(self)
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
    return self.build_configuration.conan_profile ~= nil or self.conan_profile ~= nil
end

return Profile
