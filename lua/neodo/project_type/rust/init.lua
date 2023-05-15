local M = {}

local utils = require('neodo.utils')
local notify = require('neodo.notify')
local config = require('neodo.project_type.cmake.config')
local commands = require('neodo.project_type.cmake.commands')
local log = require('neodo.log')
local Path = require('plenary.path')

M.register = function()
    local settings = require('neodo.settings')
    settings.project_types.rust = {
        name = 'Rust',
        patterns = { 'Cargo.toml' },
        commands = {
            build_debug = {
                name = "Build debug",
                cmd = {'cargo', 'build'}
            },
            build_relese = {
                name = "Build release",
                cmd = {'cargo', 'build', '--release'}
            },
            run_debug = {
                name = "Run debug",
                cmd = {'cargo', 'run'}
            },
            run_relese = {
                name = "Run release",
                cmd = {'cargo', 'run', '--release'}
            }
        },
    }
end
return M
