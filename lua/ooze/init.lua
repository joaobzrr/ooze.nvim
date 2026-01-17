local rpc = require("ooze.rpc")
local repl = require("ooze.repl")
local ts = require("ooze.ts")
local ui = require("ooze.ui")
local config = require("ooze.config")

local M = { opts = config }

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
	rpc.connect(M.opts.server.host, M.opts.server.port)
end

function M.sync_state()
	rpc.send({ op = "ping" }, function(res)
		if res.package then
			repl.set_prompt_package(res.package)
			vim.schedule(function()
				vim.cmd("redraw")
			end)
		end
	end)
end

function M.eval(sexps, opts)
	opts = opts or {}
	local code = type(sexps) == "table" and sexps or { sexps }
	if #code == 0 then
		return
	end

	repl.add_history(code)
	if not repl.is_open() then
		repl.open()
	end

	rpc.send({ op = "eval", code = code }, function(res)
		if not res.ok then
			repl.append({ ";; RPC ERROR: " .. (res.err or "unknown") })
			return
		end

		if res.package then
			repl.set_prompt_package(res.package)
		end

		local out = {}
		local prompt = repl.get_prompt_string()
		for i, val in ipairs(code) do
			if opts.echo then
				vim.list_extend(out, ui.format_echo(val, prompt))
			end
			if res.results and res.results[i] then
				vim.list_extend(out, ui.format_eval_result(res.results[i]))
			end
		end
		repl.append(out)
	end)
end

function M.eval_enclosing()
	M.eval(ts.get_enclosing_sexp() or "", { echo = true })
end

function M.eval_outermost()
	M.eval(ts.get_outermost_sexp() or "", { echo = true })
end

function M.eval_region()
	-- 1. Get visual range
	local _, sline, scol, _ = unpack(vim.fn.getpos("'<"))
	local _, eline, ecol, _ = unpack(vim.fn.getpos("'>"))

	-- Check for valid selection
	if sline == 0 or (sline == eline and scol == ecol) then
		return
	end

	-- 2. Extract smart forms
	-- (Subtract 1 for 0-indexed Treesitter rows)
	local forms = ts.get_smart_selection(sline - 1, scol - 1, eline - 1, ecol)

	-- 3. Evaluate each gathered block
	if #forms > 0 then
		M.eval(forms, { echo = true })
	else
		vim.notify("Ooze: No valid forms found in selection", vim.log.levels.WARN)
	end
end

function M.eval_buffer()
	M.eval(ts.get_all_sexps() or {}, { echo = true })
end

return M
