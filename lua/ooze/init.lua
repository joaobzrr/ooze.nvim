---@class Ooze
local M = {}

local config = require("ooze.config")
local session = require("ooze.session")
local ts = require("ooze.ts")
local repl = require("ooze.repl")

table.unpack = table.unpack or unpack -- 5.1 compatibility

-- Store config separately to persist across reloads
_G._ooze_config = _G._ooze_config or {}

---@class Ooze.Config
local default_config = {
	server = {
		host = "127.0.0.1",
		port = 4005,
	},
}

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
function M.eval(sexps)
	local code = type(sexps) == "table" and sexps or {
		sexps --[[@as string]],
	}
	if #code == 0 then
		return
	end

	if not repl.is_open() then
		repl.open()
	end

	session.eval(code, function(res)
		if not res.ok then
			repl.append({ ";; RPC ERROR: " .. (res.err or "unknown") })
			return
		end

		if res.package then
			repl.set_prompt_package(res.package)
		end

		local lines = {}
		for i, form in ipairs(code) do
			vim.list_extend(lines, vim.split(form, "\n"))
			if res.results and res.results[i] then
				local result = res.results[i]

				if result.stdout and result.stdout ~= "" then
					for _, l in ipairs(vim.split(result.stdout, "\n")) do
						if l ~= "" then
							table.insert(lines, ";; " .. l)
						end
					end
				end

				if result.ok then
					table.insert(lines, ";; " .. result.value)
				else
					local err_lines = vim.split(result.err or "Unknown Error", "\n")
					for j, l in ipairs(err_lines) do
						table.insert(lines, (j == 1 and ";; ERROR: " or ";; ") .. l)
					end
				end
			end
		end

		repl.append(lines)
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
	M.eval(ts.get_enclosing_sexp() or "")
end

---Evaluate outermost s-expression
function M.eval_outermost()
	M.eval(ts.get_outermost_sexp() or "")
end

---Evaluate visual selection
function M.eval_region()
	local _, sline, scol, _ = table.unpack(vim.fn.getpos("'<"))
	local _, eline, ecol, _ = table.unpack(vim.fn.getpos("'>"))

	if sline == 0 or (sline == eline and scol == ecol) then
		return
	end

	local forms = ts.get_selected_forms(sline - 1, scol - 1, eline - 1, ecol)

	if #forms > 0 then
		M.eval(forms)
	else
		vim.notify("Ooze: No valid forms found in selection", vim.log.levels.WARN)
	end
end

---Evaluate entire buffer
function M.eval_buffer()
	M.eval(ts.get_all_sexps() or {})
end

return M
