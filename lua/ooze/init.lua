---@class Ooze
local M = {}

-- Store config separately to persist across reloads
_G._ooze_config = _G._ooze_config or {}

---@class Ooze.Config
---@field server { host: string, port: integer }
local default_config = {
	server = {
		host = "127.0.0.1",
		port = 4005,
	},
}

---Setup function called by lazy.nvim
---@param opts? Ooze.Config
function M.setup(opts)
	-- Merge user config with defaults and store globally
	_G._ooze_config = vim.tbl_deep_extend("force", default_config, opts or {})

	-- Defer actual initialization until first use
	-- This allows the plugin to be lazy-loaded
end

---Get current config (always returns the global config)
---@return Ooze.Config
function M.get_config()
	return _G._ooze_config
end

---Reload the entire plugin, clearing all state
function M.reload()
	-- Close REPL if open
	local repl = require("ooze.repl")
	if repl.is_open() then
		repl.close()
	end

	-- Disconnect RPC
	local rpc = require("ooze.rpc")
	rpc.disconnect()

	-- Clear all ooze modules from package cache
	for name, _ in pairs(package.loaded) do
		if name:match("^ooze") then
			package.loaded[name] = nil
		end
	end

	-- Re-require and setup
	local ooze = require("ooze")
	ooze.setup(_G._ooze_config)

	vim.notify("Ooze plugin reloaded", vim.log.levels.INFO)
end

---Connect to server (lazy initialization)
local function ensure_connected()
	local rpc = require("ooze.rpc")
	if not rpc.is_connected() then
		local config = M.get_config()
		rpc.connect(config.server.host, config.server.port)
	end
end

---Sync package state with server
function M.sync_state()
	ensure_connected()
	local rpc = require("ooze.rpc")
	local repl = require("ooze.repl")

	rpc.send({ op = "ping" }, function(res)
		if res.package then
			repl.set_prompt_package(res.package)
			vim.schedule(function()
				vim.cmd("redraw")
			end)
		end
	end)
end

---Evaluate code
---@param sexps string|string[]
---@param opts? { echo?: boolean }
function M.eval(sexps, opts)
	ensure_connected()

	opts = opts or {}
	local code = type(sexps) == "table" and sexps or { sexps }
	if #code == 0 then
		return
	end

	local repl = require("ooze.repl")
	local rpc = require("ooze.rpc")
	local ui = require("ooze.ui")

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

---Evaluate enclosing s-expression
function M.eval_enclosing()
	local ts = require("ooze.ts")
	M.eval(ts.get_enclosing_sexp() or "", { echo = true })
end

---Evaluate outermost s-expression
function M.eval_outermost()
	local ts = require("ooze.ts")
	M.eval(ts.get_outermost_sexp() or "", { echo = true })
end

---Evaluate visual selection
function M.eval_region()
	local ts = require("ooze.ts")

	-- Get visual range
	local _, sline, scol, _ = unpack(vim.fn.getpos("'<"))
	local _, eline, ecol, _ = unpack(vim.fn.getpos("'>"))

	-- Check for valid selection
	if sline == 0 or (sline == eline and scol == ecol) then
		return
	end

	-- Extract smart forms (subtract 1 for 0-indexed Treesitter rows)
	local forms = ts.get_selected_forms(sline - 1, scol - 1, eline - 1, ecol)

	if #forms > 0 then
		M.eval(forms, { echo = true })
	else
		vim.notify("Ooze: No valid forms found in selection", vim.log.levels.WARN)
	end
end

---Evaluate entire buffer
function M.eval_buffer()
	local ts = require("ooze.ts")
	M.eval(ts.get_all_sexps() or {}, { echo = true })
end

return M
