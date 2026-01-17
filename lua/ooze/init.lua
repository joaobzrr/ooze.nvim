local rpc = require("ooze.rpc")
local ts = require("ooze.ts")
local config = require("ooze.config")

local M = { opts = {} }

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", config, opts or {})
	local server_opts = M.opts.server
	if server_opts and server_opts.host and server_opts.port then
		rpc.connect(server_opts.host, server_opts.port, function()
			vim.notify("Ooze: Connected to Lisp server.", vim.log.levels.INFO)
		end)
	end
end

---@private
---Formats and displays a server response in the REPL window.
---@param sexps string[] The original sexps sent to the server.
---@param res OozeRpcResponse The response table from the RPC layer.
---@param opts table
local function display_in_repl(sexps, res, opts)
	local repl = require("ooze.repl")
	if not repl.is_open() then
		repl.open()
	end

	if not res or not res.results then
		repl.append_output(";; ERROR: No response from server.")
		return
	end

	for i, code in ipairs(sexps) do
		-- 1. Show the code being evaluated
		if not opts.silent then
			local code_lines = vim.split(code, "\n")
			for j, line in ipairs(code_lines) do
				repl.append_output((j == 1 and "OOZE> " or "      ") .. line)
			end
		end

		-- 2. Show the paired result from the results array
		local result = res.results[i]
		if result then
			-- Append stdout (commented)
			if result.stdout and result.stdout ~= "" then
				local lines = vim.split(result.stdout, "\n")
				for _, line in ipairs(lines) do
					if line ~= "" then
						repl.append_output(";; " .. line)
					end
				end
			end
			-- Append value or error (commented)
			if result.ok then
				repl.append_output(";; " .. result.value)
			else
                local err_lines = vim.split(result.err, "\n")
                for j, line in ipairs(err_lines) do
                    if j == 1 then
                        repl.append_output(";; ERROR: " .. line)
                    else
                        repl.append_output(";; " .. line)
                    end
                end
			end
		end
	end
end

---@param sexps (string|string[])?
---@param opts? {silent?: boolean}
function M.eval(sexps, opts)
	if not sexps then
		return
	end

	local sexps_list = type(sexps) == "string" and { sexps } or sexps
	if #sexps_list == 0 then
		return
	end

	opts = opts or {}

	rpc.eval(sexps_list, function(res)
		display_in_repl(sexps_list, res, opts)
	end)
end

function M.eval_enclosing_sexp_at_cursor()
	M.eval(ts.get_enclosing_sexp_at_cursor())
end

function M.eval_outermost_sexp_at_cursor()
	M.eval(ts.get_outermost_sexp_at_cursor())
end

function M.eval_buffer()
	M.eval(ts.get_toplevel_sexps_in_buffer())
end

function M.open_repl()
	require("ooze.repl").open()
end

return M
