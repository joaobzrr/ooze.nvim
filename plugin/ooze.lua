if vim.g.loaded_ooze then
	return
end
vim.g.loaded_ooze = true

local ooze = require("ooze")

vim.api.nvim_create_user_command("OozeEvalEnclosingSexp", function()
	ooze.eval_enclosing_sexp_at_cursor()
end, { desc = "Evaluate the nearest enclosing Lisp sexp" })

vim.api.nvim_create_user_command("OozeEvalOutermostSexp", function()
	ooze.eval_outermost_sexp_at_cursor()
end, { desc = "Evaluate the outermost Lisp sexp" })

vim.api.nvim_create_user_command("OozeEvalBuffer", function()
	ooze.eval_buffer()
end, { desc = "Evaluate the entire buffer" })

vim.api.nvim_create_user_command("OozeReplToggle", function()
	require("ooze.repl").toggle()
end, { desc = "Toggle the Ooze REPL window." })
