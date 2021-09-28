local M = {}

local uv = vim.loop

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

function M.file_exists(file)
    local stat = uv.fs_stat(file)
    if stat ~= nil and stat.type == "file" then return true end
    return false
end

function M.dir_exists(dir)
    local stat = uv.fs_stat(dir)
    if stat ~= nil and stat.type == "directory" then return true end
    return false
end

function M.delete(path)
    if M.dir_exists(path) then
        uv.fs_rmdir(path)
    else
        if M.file_exists(path) then uv.fs_unlink(path) end
    end
end

function M.mkdir(path) uv.fs_mkdir(path, 448) end

function M.symlink(what, where)
    uv.fs_symlink(what, where)
end

return M
