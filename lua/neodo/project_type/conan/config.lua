local M = {}

local Path = require('plenary.path')
local notify = require('neodo.notify')
local log = require('neodo.log')

local conan_config_file_name = 'neodo_conan_config.json'

function M.load(project, conan_project)
    log.debug("Conan load config called")
    if not project:get_data_path() then return end

    if not conan_project then
        notify.error('Cannot load config, no conan project type found.', 'NeoDo > Conan')
        return
    end

    local config_file = Path:new(project:get_data_path(), conan_config_file_name)

    if not config_file:is_file() then
        log.debug("No conan config file found")
        return
    end

    local data = config_file:read()
    if not data then return end

    conan_project.settings = vim.fn.json_decode(data)
end

function M.save(project, conan_project, callback)
    if not project:get_data_path() then
        notify.error('Cannot save config, project config data path not found', 'NeoDo > Conan')
        return
    end

    if not conan_project then
        notify.error('Cannot save config, no conan project type found.', 'NeoDo > Conan')
        return
    end

    local config_file = Path:new(project:get_data_path(), conan_config_file_name)
    config_file:write(vim.fn.json_encode(conan_project.settings), 'w')
    notify.info('Configuration saved', 'NeoDo > Conan')
    if type(callback) == 'function' then callback(true) end
end

return M
