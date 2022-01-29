local M = {}
local config_file_name = 'config.lua'
local neodo_folder = '.neodo'
local dp = vim.fn.stdpath("data")
local base_data_path = dp .. '/neodo'
local fs = require 'neodo.file'

function M.project_hash(project_path) return vim.fn.sha256(project_path) end

local function get_out_of_source_project_data_path(project_path)
    return fs.join_path(base_data_path, M.project_hash(project_path))
end

local function get_in_the_source_project_data_path(project_path)
    return fs.join_path(project_path, neodo_folder)
end

function M.get_project_config_and_datapath(project_path)
    local in_source_dp = get_out_of_source_project_data_path(project_path)
    local in_source_config = fs.join_path(in_source_dp, config_file_name)
    if fs.file_exists(in_source_config) then
        return in_source_config, in_source_dp
    end

    local out_source_dp = get_out_of_source_project_data_path(project_path)
    local out_source_config = fs.join_path(out_source_dp, config_file_name)
    if fs.file_exists(out_source_config) then
        return out_source_dp, out_source_config
    end

    if fs.dir_exists(in_source_dp) then
        return nil, in_source_dp
    end

    if fs.dir_exists(out_source_dp) then
        return nil, out_source_dp
    end

    return nil, nil
end

local function write_template(path, template, callback)
    fs.write(path, 444, template, callback)
end

local template = [[
local M = {
--config here
}
return M
]]

local function create_config_file(data_path, callback)
    if not fs.dir_exists(data_path) then
        fs.create_directories(data_path)
    end
    local config_file = fs.join_path(data_path, config_file_name)
    write_template(config_file, template, function(err)
            if err then
                print("Cannot create config file: " .. config_file)
            else
                callback(config_file, data_path)
            end
    end)
end

function M.create_out_of_source_config_file(project_path, callback)
    local data_path = get_out_of_source_project_data_path(project_path)
    create_config_file(data_path, callback)
end

function M.create_in_the_source_config_file(project_path, callback)
    local data_path = get_in_the_source_project_data_path(project_path)
    create_config_file(data_path, callback)
end

return M
