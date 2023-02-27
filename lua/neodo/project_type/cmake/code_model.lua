local fs = require('neodo.file')
local notify = require('neodo.notify')
local Path = require('plenary.path')

local base_api_dir = Path:new('.cmake', 'api', 'v1')
local base_query_dir = Path:new(base_api_dir, 'query')
local base_reply_dir = Path:new(base_api_dir, 'reply')
local base_codemodel_file = 'codemodel-v2'

local CodeModel = {}

function CodeModel:write_query()
    if not self.query_dir:is_dir() then
        self.query_dir:mkdir({ parents = true })
    end
    local codemodel_file = Path:new(self.query_dir, base_codemodel_file)
    if not codemodel_file:exists() then
        codemodel_file:touch()
    end
end

function CodeModel:load_model_file(path, callback)
    local full_path = Path:new(self.reply_dir, path)
    fs.read(full_path:absolute(), 438, function(err, data)
        if err then
            notify.error('Cannot read code model file: ' .. path)
            return
        else
            local model = vim.fn.json_decode(data)
            callback(model)
        end
    end)
end

local function find_index_file(reply_dir)
    local items = fs.dirlist(reply_dir.filename)
    local pattern = '^index%-.*%.json$'
    for _, item in ipairs(items) do
        if string.match(item, pattern) then
            return item
        end
    end
    return nil
end

function CodeModel:parse_target_model(model)
    if model == nil or model.artifacts == nil then
        return
    end
    local paths = {}
    for _, a in ipairs(model.artifacts) do
        table.insert(paths, Path:new(self.build_dir, a.path))
    end
    self.targets[model.name] = { name = model.name, type = model.type, paths = paths }
end

function CodeModel:read_reply(callback)
    local index = find_index_file(self.reply_dir)
    if index ~= nil then
        self:load_model_file(index, function(index_model)
            self:load_model_file(index_model.reply['codemodel-v2'].jsonFile, function(code_model)
                local refs = 0
                for _, configuration in ipairs(code_model.configurations) do
                    for _, target in ipairs(configuration.targets) do
                        refs = refs + 1
                        self:load_model_file(target.jsonFile, function(target_model)
                            self:parse_target_model(target_model)
                            refs = refs - 1
                            if refs == 0 and type(callback) == 'function' then
                                callback(true)
                            end
                        end)
                    end
                end
            end)
        end)
    else
        if type(callback) == 'function' then
            callback(false)
        end
    end
end

function CodeModel:get_targets()
    return self.targets or {}
end

function CodeModel:new(build_dir)
    local o = {
        build_dir = Path:new(build_dir),
        query_dir = Path:new(build_dir, base_query_dir),
        reply_dir = Path:new(build_dir, base_reply_dir),
        targets = {},
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

return CodeModel
