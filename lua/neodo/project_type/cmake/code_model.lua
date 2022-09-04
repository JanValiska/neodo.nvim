local fs = require("neodo.file")
local notify = require("neodo.notify")

local base_api_dir = fs.join_path(".cmake", "api", "v1")
local base_query_dir = fs.join_path(base_api_dir, "query")
local base_reply_dir = fs.join_path(base_api_dir, "reply")
local base_codemodel_file = "codemodel-v2"

local CodeModel = {
}

function CodeModel:write_query()
    if not fs.dir_exists(self.query_dir) then
        fs.create_directories(self.query_dir)
    end
    local codemodel_file = fs.join_path(self.query_dir, base_codemodel_file)
    if not fs.file_exists(codemodel_file) then
        fs.touch(codemodel_file)
    end
end

function CodeModel:load_model_file(path, callback)
    local full_path = fs.join_path(self.reply_dir, path)
    fs.read(full_path, 438, function(err, data)
        if err then
            notify.error("Cannot read code model file: " .. path)
            return
        else
            local model = vim.fn.json_decode(data)
            callback(model)
        end
    end)
end

local function find_index_file(reply_dir)
    local items = fs.dirlist(reply_dir)
    local pattern = "^index%-.*%.json$"
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
        table.insert(paths, fs.join_path(self.build_dir, a.path))
    end
    self.targets[model.name] = { name = model.name, type = model.type, paths = paths }
end

function CodeModel:read_reply()
    local index = find_index_file(self.reply_dir)
    if index ~= nil then
        self:load_model_file(index, function(index_model)
            self:load_model_file(index_model.reply["codemodel-v2"].jsonFile, function(code_model)
                for _, configuration in ipairs(code_model.configurations) do
                    for _, target in ipairs(configuration.targets) do
                        self:load_model_file(target.jsonFile, function(target_model)
                            self:parse_target_model(target_model)
                        end)
                    end
                end
            end)
        end)
    end
end

function CodeModel:get_targets()
    return self.targets
end

function CodeModel:new(build_dir)
    local o = {
        build_dir = build_dir,
        query_dir = fs.join_path(build_dir, base_query_dir),
        reply_dir = fs.join_path(build_dir, base_reply_dir),
        targets = {}
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

return CodeModel
