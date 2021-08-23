local M = {}
local uv = vim.loop

local out_of_source_config_file_name = 'neodo.lua'
local in_the_source_config_file_name = '.neodo.lua'

local base_data_path = vim.fn.stdpath("data")

function M.project_hash(project_path)
    return vim.fn.sha256(project_path)
end

function M.stringize_path(project_path)
    local r, _ = string.gsub(project_path, '/', '%%')
    return r
end

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
    local project_data_path = M.get_project_data_path(project_path)
    if not dir_exists(project_path) then
        uv.fs_mkdir(project_data_path, 448, callback)
    else
        callback()
    end
end

function M.get_data_path() return base_data_path end

function M.get_project_data_path(project_path)
    return base_data_path .. '/' .. M.stringize_path(project_path)
end

function M.get_project_out_of_source_config(project_path)
    return M.get_project_data_path(project_path) .. '/' ..
               out_of_source_config_file_name
end

function M.get_project_in_the_source_config(project_path)
    return project_path .. '/' .. in_the_source_config_file_name
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

function M.create_out_of_source_config_file(project_path, callback)
    ensure_project_data_path(project_path, function()
        local config_file = M.get_project_out_of_source_config(project_path)
        local fd = uv.fs_open(config_file, "w")
        uv.fs_close(fd)
        callback(config_file)
    end)
end

function M.create_in_the_source_config_file(project_path, callback)
    local config_file = M.get_project_in_the_source_config(project_path)
    local fd = uv.fs_open(config_file, "w")
    uv.fs_close(fd)
    callback(config_file)
end

return M
