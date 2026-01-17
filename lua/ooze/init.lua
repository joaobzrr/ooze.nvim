local rpc = require("ooze.rpc")
local repl = require("ooze.repl")
local ts = require("ooze.ts")
local config = require("ooze.config")

---@class Ooze
local M = { opts = {} }

---@param result Ooze.EvalResult
---@return string[]
local function format_result_lines(result)
	local lines = {}
	if result.stdout and result.stdout ~= "" then
		for _, l in ipairs(vim.split(result.stdout, "\n")) do
			if l ~= "" then
				table.insert(lines, ";; " .. l)
			end
		end
	end
	if result.ok then
		table.insert(lines, ";; " .. (result.value or "nil"))
	else
		table.insert(lines, ";; ERROR: " .. (result.err or "Unknown"))
	end
	return lines
end

---@param sexps (string | string[])?
---@param opts? Ooze.EvalOpts
function M.eval(sexps, opts)
	opts = opts or {}
	local list = type(sexps) == "string" and { sexps } or sexps
	if not list or #list == 0 then
		return
	end

	if not repl.is_open() then
		repl.open()
	end

	rpc.eval(list, function(res)
		if not res or not res.results then
			repl.append({ ";; ERROR: No response from server" })
			return
		end

		local output = {}
		for i, code in ipairs(list) do
			if not opts.silent then
				local code_lines = vim.split(code, "\n")
				for j, line in ipairs(code_lines) do
					table.insert(output, (j == 1 and "OOZE> " or "      ") .. line)
				end
			end
			vim.list_extend(output, format_result_lines(res.results[i]))
		end
		repl.append(output)
	end)
end

---@param opts? table
function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", config, opts or {})
	rpc.connect(M.opts.server.host, M.opts.server.port)
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

return M
