---@module 'ooze.plugin'

if vim.g.loaded_ooze then
	return
end
vim.g.loaded_ooze = true

local ooze = require("ooze")

vim.api.nvim_create_user_command("OozeEvalForm", function()
	ooze.eval_nearest_form_at_cursor()
end, {
	nargs = 0,
	desc = "Evaluate the nearest enclosing Lisp form at the cursor",
})

vim.api.nvim_create_user_command("OozeEvalTopLevel", function()
	ooze.eval_outermost_form_at_cursor()
end, {
	nargs = 0,
	desc = "Evaluate the top-level Lisp form containing the cursor",
})
