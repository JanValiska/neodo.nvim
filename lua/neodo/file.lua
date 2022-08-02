local M = {}

M.separator = '/';

local uv = vim.loop

local function split (inputstr, sep)
        if sep == nil then
                sep = "%s"
        end
        local t={}
        for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
                table.insert(t, str)
        end
        return t
end

function M.read(path, mode, callback)
    uv.fs_open(path, "r", mode, function(err, fd)
        if err then
            callback(1, nil)
        else
            uv.fs_fstat(fd, function(err1, stat)
                if err1 then
                    callback(2, nil)
                else
                    uv.fs_read(fd, stat.size, 0, function(err2, data)
                        if err2 then
                            callback(3, nil)
                        else
                            uv.fs_close(fd, function(err3)
                                if err3 then
                                    callback(4, nil)
                                else
                                    vim.schedule(function()
                                        callback(nil, data)
                                    end)
                                end
                            end)
                        end
                    end)
                end
            end)
        end
    end)
end

function M.write(path, mode, data, callback)
    uv.fs_open(path, "w", mode, function(err, fd)
        if err then
            callback(1)
        else
            uv.fs_write(fd, data, 0, function(err1, _)
                if err1 then
                    callback(2)
                else
                    uv.fs_close(fd, function(err2)
                        if err2 then
                            callback(3)
                        else
                            vim.schedule(function()
                                callback(nil)
                            end)
                        end
                    end)
                end
            end)
        end
    end)
end

function M.join_path(first, ...)
    local p = first
    for _, value in ipairs({...}) do
        p = p .. M.separator .. value
    end
    return p;
end

function M.file_exists(file)
    local stat = uv.fs_stat(file)
    return stat ~= nil and stat.type == "file"
end

function M.dir_exists(dir)
    local stat = uv.fs_stat(dir)
    return stat ~= nil and stat.type == "directory"
end

local function rmdir(path)
    local stat = uv.fs_stat(path)
    if stat ~= nil and stat.type == 'directory' then
        local handle = uv.fs_scandir(path)
        while true do
            local item = uv.fs_scandir_next(handle)
            if item ~= nil then
                local p = path .. M.separator .. item
                rmdir(p)
            else
                goto empty
            end
        end
        ::empty::
        uv.fs_rmdir(path)
    else
        uv.fs_unlink(path)
    end
end

function M.delete(path)
    if M.dir_exists(path) then
        rmdir(path)
    else
        if M.file_exists(path) then uv.fs_unlink(path) end
    end
end

function M.mkdir(path) uv.fs_mkdir(path, 448) end

local function starts_by_root(p)
    return string.sub(p, 1, 1) == '/'
end

local function create_directories_from_table(t, root)
    local p = ''
    if root then
        p = '/'
    end
    for index, dir  in ipairs(t) do
       if index == 1 then
           p = p .. dir
       else
           p = M.join_path(p, dir)
       end
       if not M.dir_exists(p) then
           M.mkdir(p)
       end
    end
end

function M.create_directories(dir)
    local dirs = split(dir, M.separator)
    create_directories_from_table(dirs, starts_by_root(dir))
end

function M.touch(path)
    M.write(path, 444, '', function() end)
end

function M.symlink(what, where)
    uv.fs_symlink(what, where)
end

function M.dirlist(dir)
    local items = {}
    if M.dir_exists(dir) then
        local handle = uv.fs_scandir(dir)
        while true do
            local item = uv.fs_scandir_next(handle)
            if item ~= nil then
            table.insert(items, item)
            else
                goto last
            end
        end
        ::last::
    end
    return items
end

return M
