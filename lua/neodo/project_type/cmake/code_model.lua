local notify = require('neodo.notify')
local Path = require('plenary.path')
local scandir = require('plenary.scandir')

local base_api_dir = Path:new('.cmake', 'api', 'v1')
local base_query_dir = Path:new(base_api_dir, 'query')
local base_reply_dir = Path:new(base_api_dir, 'reply')
local base_codemodel_file = 'codemodel-v2'

local CodeModel = {}

function CodeModel:write_query()
    if not self.query_dir:is_dir() then self.query_dir:mkdir({ parents = true }) end
    local codemodel_file = Path:new(self.query_dir, base_codemodel_file)
    if not codemodel_file:exists() then codemodel_file:touch() end
end

function CodeModel:load_model_file(path, callback)
    local full_path = Path:new(path)
    if not full_path:exists() then notify.error('Model file missing:', full_path:absolute()) end
    local data = full_path:read()
    if not data then
        notify.error('Cannot read: ', full_path:absolute())
        return
    end
    local model = vim.fn.json_decode(data)
    callback(model)
end

local function find_index_file(reply_dir)
    local pattern = '.*index%-.*%.json$'
    local function filter(item) return string.match(item, pattern) end

    local items = scandir.scan_dir(reply_dir:absolute(), {
        search_pattern = filter,
        hidden = true,
    })
    if items then
        assert(vim.tbl_count(items) == 1, 'None or multiple index files found')
        return items[1]
    end
    return nil
end

function CodeModel:parse_target_model(model)
    if model == nil or model.artifacts == nil then return end
    local paths = {}
    for _, a in ipairs(model.artifacts) do
        table.insert(paths, Path:new(self.build_dir, a.path))
    end
    self.targets[model.name] = { name = model.name, type = model.type, paths = paths }
end

function CodeModel:read_reply(callback)
    local index = find_index_file(self.reply_dir)
    if index == nil then
        if type(callback) == 'function' then callback(false) end
        return
    end

    self:load_model_file(index, function(index_model)
        self:load_model_file(
            Path:new(self.reply_dir, index_model.reply['codemodel-v2'].jsonFile):absolute(),
            function(code_model)
                local refs = 0
                for _, configuration in ipairs(code_model.configurations) do
                    for _, target in ipairs(configuration.targets) do
                        refs = refs + 1
                        self:load_model_file(
                            Path:new(self.reply_dir, target.jsonFile):absolute(),
                            function(target_model)
                                self:parse_target_model(target_model)
                                refs = refs - 1
                                if refs == 0 and type(callback) == 'function' then
                                    callback(true)
                                end
                            end
                        )
                    end
                end
            end
        )
    end)
end

function CodeModel:get_targets() return self.targets or {} end

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
