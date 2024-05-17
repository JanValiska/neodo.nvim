local M = {}

M.get_errorformat = function(compiler)
    if compiler == "gcc" then
        return '%-G%f:%s:,' ..
            '%-G%f:%l: %#error: %#(Each undeclared identifier is reported only%.%#,' ..
             '%-G%f:%l: %#error: %#for each function it appears%.%#,' ..
             '%-GIn file included%.%#,' ..
             '%-G %#from %f:%l,' ..
             '%f:%l:%c: %trror: %m,' ..
             '%f:%l:%c: %tarning: %m,' ..
             '%I%f:%l:%c: note: %m,' ..
             '%f:%l:%c: %m,' ..
             '%f:%l: %trror: %m,' ..
             '%f:%l: %tarning: %m,'..
             '%I%f:%l: note: %m,'..
             '%f:%l: %m'
    end
	vim.cmd("compiler " .. compiler)
	return vim.o.errorformat
end

return M
