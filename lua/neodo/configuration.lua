local M = {}
local config_file_name = 'config.lua'
local neodo_folder = '.neodo'
local dp = vim.fn.stdpath('data')
local base_data_path = dp .. '/neodo'
local settings = require('neodo.settings')
local log = require('neodo.log')
local Path = require('plenary.path')

function M.project_hash(project_path) return vim.fn.sha256(project_path) end

local function make_percent_path(path)
    local paaa = Path:new(path)
    local sep = paaa._sep
    if string.sub(path, 1, 1) == sep then path = path:sub(2) end
    local p = path:gsub(sep, '-')
    return p
end

local function get_out_of_source_project_data_path(project_path)
    return Path:new(base_data_path, make_percent_path(project_path))
end

local function get_in_the_source_project_data_path(project_path)
    return Path:new(project_path, neodo_folder)
end

function M.get_project_config_and_datapath(project_path)
    local in_source_dp = get_in_the_source_project_data_path(project_path)
    local in_source_config = Path:new(in_source_dp, config_file_name)
    if in_source_config:exists() then
        return in_source_config:absolute(), in_source_dp:absolute()
    end

    local out_source_dp = get_out_of_source_project_data_path(project_path)
    local out_source_config = Path:new(out_source_dp, config_file_name)
    if out_source_config:exists() then
        return out_source_config:absolute(), out_source_dp:absolute()
    end

    if in_source_dp:exists() and in_source_dp:is_dir() then return nil, in_source_dp:absolute() end

    if out_source_dp:exists() and out_source_dp:is_dir() then
        return nil, out_source_dp:absolute()
    end

    return nil, nil
end

local template = [[
local M = {
--config here
}
return M
]]

local function create_config_file(data_path, callback)
    if not data_path:exists() then data_path:mkdir({ parents = true }) end
    local config_file = Path:new(data_path, config_file_name)
    config_file:write(template, 'w')
    if not config_file:exists() then
        print('Cannot create config file: ' .. config_file)
        callback(nil, nil)
        return
    end
    callback(config_file, data_path)
end

local function create_out_of_source_config_file(project_path, callback)
    local data_path = get_out_of_source_project_data_path(project_path)
    create_config_file(data_path, callback)
end

local function create_in_the_source_config_file(project_path, callback)
    local data_path = get_in_the_source_project_data_path(project_path)
    create_config_file(data_path, callback)
end

function M.ensure_config_file_and_data_path(project, callback)
    local f = create_out_of_source_config_file
    if settings.use_in_the_source_config then f = create_in_the_source_config_file end

    f(project:get_path(), callback)
end

return M
