---@module 'ooze'

local rpc = require("ooze.rpc")
local config = require("ooze.config")

local M = {}

---@type OozeConfig The merged configuration for the plugin.
M.opts = {}

---The main setup function for the plugin.
---Users will call this from their init.lua file.
---@param opts OozeConfig? User-provided configuration overrides.
function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", config, opts or {})

	---@type OozeConfigServer
	local server_opts = M.opts.server
	if server_opts and server_opts.host and server_opts.port then
		rpc.connect(server_opts.host, server_opts.port, function()
			vim.notify("Ooze: Connected to Lisp server.", vim.log.levels.INFO)
		end)
	else
		vim.notify("Ooze: Server host or port not configured.", vim.log.levels.ERROR)
	end
end

---Evaluates the current line of code.
function M.eval_current_line()
	local line = vim.api.nvim_get_current_line()

	local package = "common-lisp-user"

	rpc.send(line, package, function(res)
		---@param res OozeRpcResponse
		if not res then
			vim.notify("Ooze Eval Error: No response from server.", vim.log.levels.ERROR)
			return
		end

		if res.err then
			vim.notify("Ooze Eval Error: " .. res.err, vim.log.levels.ERROR)
			return
		end

		print("Ooze Eval Result:")
		print(vim.inspect(res))
	end)
end

return M
