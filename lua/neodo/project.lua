local log = require('neodo.log')
local utils = require('neodo.utils')
local runner = require('neodo.runner')

local M = {}

local function merge_custom_config(config, custom_config)
    if custom_config == nil then
        return config
    end
    return vim.tbl_deep_extend("force", config, custom_config)
end

local function strip_user_project_settings(user_settings)
    if user_settings == nil then
        return
    end
    local to_strip = { 'path', 'hash', 'data_path', 'config_file', 'last_command' }
    for _, v in ipairs(to_strip) do
        user_settings[v] = nil
    end
end

local function fix_command_names(project)
    if project.commands then
        for key, command in pairs(project.commands) do
            if not command.name then
                command.name = key
            end
        end
    end

    for _, project_type in pairs(project.project_types) do
        if project_type.commands then
            for key, command in pairs(project_type.commands) do
                if not command.name then
                    command.name = key
                end
            end
        end
    end
end

local function split_command_key(command_key)
    local items = utils.split_string(command_key, '.')
    if items[2] then
        return { project_type = items[1], key = items[2] }
    end
    return { project_type = nil, key = items[1] }
end

local function command_enabled(command, project, project_type)
    if command.enabled and type(command.enabled) == "function" then
        return command.enabled({params = command.params, project = project, project_type = project_type})
    end
    return true
end

function M.new(path, hash, data_path, config_file, project_types, user_project_settings)
    strip_user_project_settings(user_project_settings)

    local self = {
        path = path,
        hash = hash,
        data_path = data_path,
        config_file = config_file,
        last_command = nil,
        on_attach = nil,
        buffer_on_attach = nil,
        project_types = project_types,
        commands = {}
    }

    self = merge_custom_config(self, user_project_settings)

    fix_command_names(self)

    local p = {}

    function p.path()
        return self.path
    end

    function p.hash()
        return self.hash
    end

    function p.data_path()
        return self.data_path
    end

    function p.set_data_path(dpath)
        self.data_path = dpath
    end

    function p.config_file()
        return self.config_file
    end

    function p.set_config_file(file)
        self.config_file = file
    end

    function p.project_types()
        return self.project_types
    end

    function p.run(command_key)
        if type(command_key) ~= "string" or command_key == '' then
            log.warning("Wrong command key")
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

        if not command_enabled(command, p, project_type) then
            log.warning("Command disabled")
            return
        end

        if runner.run_project_command(command, p, project_type) then
            self.last_command = command_key
        end
    end

    function p.run_last_command()
        if not self.last_command then
            log.warning("No last command defined")
            return
        end
        p.run(self.last_command)
    end

    function p.buffer_on_attach(bufnr)
        for _, t in pairs(self.project_types) do
            if t.buffer_on_attach and type(t.buffer_on_attach) == "function" then
                t.buffer_on_attach({bufnr = bufnr, project = p, project_type = t})
            end
        end
        if self.buffer_on_attach and type(self.buffer_on_attach) == "function" then
            self.buffer_on_attach({bufnr = bufnr, project = p})
        end
    end

    function p.on_attach()
        for _, t in pairs(self.project_types) do
            if t.on_attach and type(t.on_attach) == "function" then
                t.on_attach({project = p, project_type = t})
            end
        end
        if self.on_attach and type(self.on_attach) == "function" then
            self.on_attach({project = p})
        end
    end

    function p.get_commands_keys_names()
        local keys_names = {}
            for key, command in pairs(self.commands) do
                if command_enabled(command, p) then
                    table.insert(keys_names, { key = key, name = "Custom: " .. command.name })
                end
            end
        for project_type_key, project_type in pairs(self.project_types) do
            if project_type.commands then
                for command_key, command in pairs(project_type.commands) do
                    if command_enabled(command, p, project_type) then
                        table.insert(keys_names,
                            { key = project_type_key .. "." .. command_key,
                                name = project_type.name .. ": " .. command.name })
                    end
                end
            end
        end
        return keys_names
    end

    function p.get_commands_keys()
        local keys = {}
        if p.commands then
            for key, command in pairs(p.commands) do
                if command_enabled(command, p) then
                    table.insert(keys, key)
                end
            end

        end
        for project_type_key, project_type in pairs(p.project_types) do
            if project_type.commands then
                for command_key, command in pairs(project_type.commands) do
                    if command_enabled(command, p, project_type) then
                        table.insert(keys, project_type_key .. '.' .. command_key)
                    end
                end
            end
        end
        return keys
    end

    function p.project_types_keys()
        return vim.tbl_keys(self.project_types)
    end

    return p
end

return M
