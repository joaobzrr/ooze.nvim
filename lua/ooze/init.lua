local rpc = require("ooze.rpc")
local ts = require("ooze.ts")
local config = require("ooze.config")

local M = {}
M.opts = {}

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", config, opts or {})
	local server_opts = M.opts.server
	if server_opts and server_opts.host and server_opts.port then
		rpc.connect(server_opts.host, server_opts.port, function()
			vim.notify("Ooze: Connected to Lisp server.", vim.log.levels.INFO)
		end)
	end
end

---Displays evaluation results from the server response
local function display_results(res)
	if not res then
		vim.notify("Ooze: No response from server.", vim.log.levels.ERROR)
		return
	end

	if res.err then
		vim.notify("Ooze RPC Error: " .. res.err, vim.log.levels.ERROR)
		return
	end

	if not res.results or #res.results == 0 then
		vim.notify("Ooze: No results.", vim.log.levels.WARN)
		return
	end

	-- If there's only one result (common case for sexp eval), show it simply
	if #res.results == 1 then
		local result = res.results[1]
		if result.ok then
			vim.notify("=> " .. result.value, vim.log.levels.INFO)
		else
			vim.notify("Error: " .. result.err, vim.log.levels.ERROR)
		end
	else
		-- Multiple results (for Buffer eval)
		local lines = { "Buffer Results:" }
		for i, r in ipairs(res.results) do
			local status = r.ok and "OK" or "ERR"
			local val = r.ok and r.value or r.err
			table.insert(lines, string.format("%d [%s]: %s", i, status, val))
		end
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end
end

function M.eval(code)
	if not code or code == "" then
		return
	end
	rpc.eval(code, display_results)
end

function M.eval_enclosing_sexp_at_cursor()
	M.eval(ts.get_enclosing_sexp_at_cursor())
end

function M.eval_outermost_sexp_at_cursor()
	M.eval(ts.get_outermost_sexp_at_cursor())
end

function M.eval_buffer()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	M.eval(table.concat(lines, "\n"))
end

return M
