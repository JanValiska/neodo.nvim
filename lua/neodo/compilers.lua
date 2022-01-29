local M = {}

M.get_errorformat = function(compiler)
	vim.cmd("compiler " .. compiler)
	return vim.o.errorformat
end

return M
