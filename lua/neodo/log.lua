return function(...)
    if NeodoDebugEnabled then print((debug.getinfo(2).name or 'unknown') .. ':', ...) end
end
