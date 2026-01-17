if vim.g.loaded_ooze then
	return
end
vim.g.loaded_ooze = true

local ooze = require("ooze")
local repl = require("ooze.repl")

local cmds = {
	OozeEvalEnclosingSexp = ooze.eval_enclosing_sexp_at_cursor,
	OozeEvalOutermostSexp = ooze.eval_outermost_sexp_at_cursor,
	OozeEvalBuffer = ooze.eval_buffer,
	OozeReplToggle = repl.toggle, -- Changed to toggle
	OozeReplClear = repl.clear, -- Added clear
}

for name, fn in pairs(cmds) do
	vim.api.nvim_create_user_command(name, fn, {})
end
