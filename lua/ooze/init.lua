---@module 'ooze'

local rpc = require("ooze.rpc")
local ts = require('ooze.ts')
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

---@param code string?
local function eval_code(code)
    if not code or code == "" then
        vim.notify("Ooze: No form found at cursor.", vim.log.levels.WARN)
        return
    end

    rpc.send(code, function(res)
        if not res then
            vim.notify("Ooze Eval Error: No response from server.", vim.log.levels.ERROR)
            return
        end

        if res.err then
            vim.notify("Ooze Eval Error: " .. res.err, vim.log.levels.ERROR)
            return
        end

        vim.notify(
            "Ooze Eval Result:\n" .. vim.inspect(res),
            vim.log.levels.INFO
        )
    end)
end

function M.eval_nearest_form_at_cursor()
    eval_code(ts.get_nearest_form_at_cursor())
end

---Evaluates the outermost Lisp form at the cursor's position.
function M.eval_outermost_form_at_cursor()
    eval_code(ts.get_outermost_form_at_cursor())
end

return M
