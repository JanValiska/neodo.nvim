local notify = require('neodo.notify')
local utils = require('neodo.utils')
local runner = require('neodo.runner')
local configuration = require('neodo.configuration')
local Path = require('plenary.path')

local Project = {}

local function merge_custom_config(config, custom_config)
    if custom_config == nil then return config end
    return utils.tbl_deep_extend('force', config, custom_config)
end

local function strip_user_project_settings(user_settings)
    if user_settings == nil then return end
    local to_strip = { 'path', 'hash', 'data_path', 'config_file', 'last_command' }
    for _, v in ipairs(to_strip) do
        user_settings[v] = nil
    end
end

local function fix_command_names(project)
    if project.commands then
        for key, command in pairs(project.commands) do
            if not command.name then command.name = key end
        end
    end

    for _, project_type in pairs(project.project_types) do
        if project_type.commands then
            for key, command in pairs(project_type.commands) do
                if not command.name then command.name = key end
            end
        end
    end
end

local function split_command_key(command_key)
    local items = utils.split_string(command_key, '.')
    if items[2] then return { project_type = items[1], key = items[2] } end
    return { project_type = nil, key = items[1] }
end

local function command_enabled(command, project, project_type)
    if command.enabled and type(command.enabled) == 'function' then
        return command.enabled({
            params = command.params,
            project = project,
            project_type = project_type,
        })
    end
    return true
end

local function table_copy(datatable)
    local new_datatable = {}
    if type(datatable) == 'table' and not vim.tbl_islist(datatable) then
        for k, v in pairs(datatable) do
            new_datatable[k] = table_copy(v)
        end
    else
        new_datatable = datatable
    end
    return new_datatable
end

function Project:new(global_settings, path, types)
    local function to_absolute(p) return Path:new(Path:new(p):absolute()):absolute() end

    local props = {
        path = to_absolute(path),
        hash = configuration.project_hash(path),
        data_path = nil,
        config_file = nil,
        last_command = nil,
        commands = {},
        on_attach = {},
        buffer_on_attach = {},
        project_types = {},
    }

    -- apply global settings
    props.commands = table_copy(global_settings.commands)
    props.on_attach = vim.list_extend(props.on_attach, global_settings.on_attach or {})
    props.buffer_on_attach =
        vim.list_extend(props.buffer_on_attach, global_settings.buffer_on_attach or {})
    for key, type_path in pairs(types) do
        props.project_types[key] = table_copy(global_settings.project_types[key])
        props.project_types[key].path = to_absolute(type_path)
    end

    -- apply project specific settings
    props.config_file, props.data_path =
        configuration.get_project_config_and_datapath(props.path)
    if props.config_file ~= nil then
        local user_project_settings = dofile(props.config_file) or {}
        strip_user_project_settings(user_project_settings)
        props = merge_custom_config(props, user_project_settings)
    end

    fix_command_names(props)

    setmetatable(props, self)
    self.__index = self
    return props
end

function Project:get_path() return self.path end

function Project:get_hash() return self.hash end

function Project:get_data_path() return self.data_path end

function Project:get_config_file() return self.config_file end

function Project:create_config_file(callback)
    if self.config_file and self.data_path then
        callback(true)
    else
        configuration.ensure_config_file_and_data_path(self, function(config_file, data_path)
            self.config_file = config_file
            self.data_path = data_path
            if self.config_file and self.data_path then
                callback(true)
            else
                callback(false)
            end
        end)
    end
end

function Project:get_project_types() return self.project_types end

function Project:run(command_key)
    if type(command_key) ~= 'string' or command_key == '' then
        notify.warning('Wrong command key')
        return
    end

    local splitted_command_key = split_command_key(command_key)
    local project_type = nil
    local command = nil
    if splitted_command_key.project_type then
        project_type = self.project_types[splitted_command_key.project_type]
        command = project_type.commands[splitted_command_key.key]
    else
        command = self.commands[splitted_command_key.key]
    end

    if not command_enabled(command, self, project_type) then
        notify.warning('Command disabled')
        return
    end

    if runner.run_project_command(command, self, project_type) then
        self.last_command = command_key
    end
end

function Project:run_last_command()
    if not self.last_command then
        notify.warning('No last command defined')
        return
    end
    self:run(self.last_command)
end

function Project:call_buffer_on_attach(bufnr)
    for _, t in pairs(self.project_types) do
        if t.buffer_on_attach and type(t.buffer_on_attach) == 'table' then
            for _, f in ipairs(t.buffer_on_attach) do
                if type(f) == 'function' then
                    f({ bufnr = bufnr, project = self, project_type = t })
                end
            end
        end
    end
    if self.buffer_on_attach and type(self.buffer_on_attach) == 'table' then
        for _, f in ipairs(self.buffer_on_attach) do
            if type(f) == 'function' then f({ bufnr = bufnr, project = self }) end
        end
    end
end

function Project:call_on_attach()
    for _, t in pairs(self.project_types) do
        if t.on_attach and type(t.on_attach) == 'table' then
            for _, f in ipairs(t.on_attach) do
                if type(f) == 'function' then f({ project = self, project_type = t }) end
            end
        end
    end
    if self.on_attach and type(self.on_attach) == 'table' then
        for _, f in ipairs(self.on_attach) do
            if type(f) == 'function' then f({ project = self }) end
        end
    end
end

function Project:get_commands_keys_names()
    local keys_names = {}
    for key, command in pairs(self.commands) do
        if command_enabled(command, self) then
            table.insert(keys_names, { key = key, name = 'Global: ' .. command.name })
        end
    end
    for project_type_key, project_type in pairs(self.project_types) do
        if project_type.commands then
            for command_key, command in pairs(project_type.commands) do
                if command_enabled(command, self, project_type) then
                    local pt_name = project_type_key
                    if type(project_type.name) == 'string' then
                        pt_name = project_type.name
                    elseif type(project_type.name) == 'function' then
                        pt_name = project_type.name()
                    end
                    table.insert(
                        keys_names,
                        {
                            key = project_type_key .. '.' .. command_key,
                            name = pt_name .. ': ' .. command.name,
                        }
                    )
                end
            end
        end
    end
    table.sort(keys_names, function(a,b) return a.name < b.name end)
    return keys_names
end

function Project:get_commands_keys()
    local keys = {}
    for key, command in pairs(self.commands) do
        if command_enabled(command, self) then table.insert(keys, key) end
    end
    for project_type_key, project_type in pairs(self.project_types) do
        if project_type.commands then
            for command_key, command in pairs(project_type.commands) do
                if command_enabled(command, self, project_type) then
                    table.insert(keys, project_type_key .. '.' .. command_key)
                end
            end
        end
    end
    table.sort(keys)
    return keys
end

function Project:get_project_types_keys() return vim.tbl_keys(self.project_types) end

function Project:get_project_types_paths()
    local types = {}
    for key, t in pairs(self.project_types) do
        types[key] = t.path
    end
    return types
end

return Project
