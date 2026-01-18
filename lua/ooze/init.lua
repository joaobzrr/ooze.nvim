---@class Ooze
local M = {}

local config = require("ooze.config")
local session = require("ooze.session")
local ts = require("ooze.ts")

local repl = require("ooze.repl")
repl.setup({
	on_submit = function(code)
		M.eval(code, { echo = false })
	end,
})

-- Store config separately to persist across reloads
_G._ooze_config = _G._ooze_config or {}

---@class Ooze.Config
local default_config = {
	server = {
		host = "127.0.0.1",
		port = 4005,
	},
}

---@param result Ooze.EvalResult
---@return string[]
local function format_eval_result(result)
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
		local err_lines = vim.split(result.err or "Unknown Error", "\n")
		for i, l in ipairs(err_lines) do
			table.insert(lines, (i == 1 and ";; ERROR: " or ";; ") .. l)
		end
	end
	return lines
end

---@param code string
---@param prompt string
---@return string[]
local function format_echo(code, prompt)
	local lines = {}
	local code_lines = vim.split(code, "\n")
	local indent = string.rep(" ", #prompt)
	for i, line in ipairs(code_lines) do
		table.insert(lines, (i == 1 and prompt or indent) .. line)
	end
	return lines
end

---Setup function called by lazy.nvim
---@param opts? Ooze.Config
function M.setup(opts)
	config.setup(opts)
end

---Get current config (always returns the global config)
---@return Ooze.Config
function M.get_config()
	return config.get_config()
end

---Reload the entire plugin, clearing all state
function M.reload()
	if repl.is_open() then
		repl.close()
	end
	repl.cleanup()

	session.disconnect()

	for name, _ in pairs(package.loaded) do
		if name:match("^ooze") then
			package.loaded[name] = nil
		end
	end

	local old_cfg = config.get_config()
	M.setup(old_cfg)

	vim.notify("Ooze plugin reloaded", vim.log.levels.INFO)
end

---@param sexps string | string[]
---@param opts Ooze.EvalOpts
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

	local function append_async(lines)
		vim.schedule(function()
			repl.append(lines)
		end)
	end

	session.eval(code, function(res)
		if not res.ok then
			append_async({ ";; RPC ERROR: " .. (res.err or "unknown") })
			return
		end

		if res.package then
			repl.set_prompt_package(res.package)
		end

		local out = {}
		local prompt = repl.get_prompt_string()
		for i, val in ipairs(code) do
			if opts.echo then
				vim.list_extend(out, format_echo(val, prompt))
			end
			if res.results and res.results[i] then
				vim.list_extend(out, format_eval_result(res.results[i]))
			end
		end
		append_async(out)
	end)
end

function M.toggle_repl()
	if repl.is_open() then
		repl.close()
		return
	end

	session.connect()
	session.ping(function(res)
		if res.package then
			repl.set_prompt_package(res.package)
		end
		repl.open()
	end)
end

---Evaluate enclosing s-expression
function M.eval_enclosing()
	M.eval(ts.get_enclosing_sexp() or "", { echo = true })
end

---Evaluate outermost s-expression
function M.eval_outermost()
	M.eval(ts.get_outermost_sexp() or "", { echo = true })
end

---Evaluate visual selection
function M.eval_region()
	local _, sline, scol, _ = unpack(vim.fn.getpos("'<"))
	local _, eline, ecol, _ = unpack(vim.fn.getpos("'>"))

	if sline == 0 or (sline == eline and scol == ecol) then
		return
	end

	local forms = ts.get_selected_forms(sline - 1, scol - 1, eline - 1, ecol)

	if #forms > 0 then
		M.eval(forms, { echo = true })
	else
		vim.notify("Ooze: No valid forms found in selection", vim.log.levels.WARN)
	end
end

---Evaluate entire buffer
function M.eval_buffer()
	M.eval(ts.get_all_sexps() or {}, { echo = true })
end

return M
