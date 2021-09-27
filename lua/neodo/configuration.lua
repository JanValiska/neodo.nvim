local M = {}
local uv = vim.loop

local config_file_name = 'config.lua'

local dp = vim.fn.stdpath("data")
local base_data_path = dp .. '/neodo'
local file = require 'neodo.file'

function M.project_hash(project_path) return vim.fn.sha256(project_path) end

local function dir_exists(dir)
    local stat = uv.fs_stat(dir)
    if stat ~= nil and stat.type == "directory" then return true end
    return false
end

local function file_exists(file)
    local stat = uv.fs_stat(file)
    if stat ~= nil and stat.type == "file" then return true end
    return false
end

local function ensure_project_data_path(project_path, callback)
    if dir_exists(base_data_path) == false then
        uv.fs_mkdir(base_data_path, 448)
    end

    local project_data_path = M.get_project_data_path(project_path)
    if dir_exists(project_data_path) == false then
        uv.fs_mkdir(project_data_path, 448)
    end
    callback()
end

function M.get_project_in_source_data_path(project_path)
    return project_path .. '/' .. '.neodo'
end

local function ensure_in_source_project_data_path(project_path, callback)
    local project_data_path = M.get_project_in_source_data_path(project_path)
    if dir_exists(project_data_path) == false then
        uv.fs_mkdir(project_data_path, 448)
    end
    callback()
end

function M.get_data_path() return base_data_path end

function M.get_project_data_path(project_path)
    return base_data_path .. '/' .. M.project_hash(project_path)
end

function M.get_project_out_of_source_config(project_path)
    return M.get_project_data_path(project_path) .. '/' .. config_file_name
end

function M.get_project_in_the_source_config(project_path)
    return project_path .. '/.neodo/' .. config_file_name
end

function M.has_project_data_path(project_path)
    local project_data_path = M.get_project_data_path(project_path)
    if dir_exists(project_data_path) then return true end
    return false
end

function M.has_project_out_of_source_config(project_path)
    local out_of_source_config_path = M.get_project_out_of_source_config(
                                          project_path)
    if file_exists(out_of_source_config_path) then return true end
    return false
end

function M.has_project_in_the_source_config(project_path)
    local in_the_source_config_file = M.get_project_in_the_source_config(
                                          project_path)
    if file_exists(in_the_source_config_file) then return true end
    return false
end

local function write_template(path, template, callback)
    file.write(path, 444, template, callback)
end

local out_of_source_template = [[
local M = {
--config here
}
return M
]]

local in_the_source_template = [[
#!/usr/bin/lua
local M = {
--config here
}
return M
]]

function M.create_out_of_source_config_file(project_path, callback)
    ensure_project_data_path(project_path, function()
        local config_file = M.get_project_out_of_source_config(project_path)
        write_template(config_file, out_of_source_template, function(err)
            if err then
                print("Cannot create config file: " .. config_file)
            else
                callback(config_file)
            end
        end)
    end)
end

function M.create_in_the_source_config_file(project_path, callback)
    ensure_in_source_project_data_path(project_path, function()
        local config_file = M.get_project_in_the_source_config(project_path)
        write_template(config_file, in_the_source_template, function(err)
            if err then
                print("Cannot create config file: " .. config_file)
            else
                callback(config_file)
            end
        end)
    end)
end

return M
