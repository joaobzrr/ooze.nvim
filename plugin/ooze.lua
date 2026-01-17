if vim.g.loaded_ooze then
	return
end
vim.g.loaded_ooze = true

local ooze = require("ooze")
local repl = require("ooze.repl")

vim.api.nvim_create_user_command("OozeEvalEnclosing", ooze.eval_enclosing, {})
vim.api.nvim_create_user_command("OozeEvalOutermost", ooze.eval_outermost, {})
vim.api.nvim_create_user_command("OozeEvalBuffer", ooze.eval_buffer, {})
vim.api.nvim_create_user_command("OozeReplToggle", repl.toggle, {})
vim.api.nvim_create_user_command("OozeReplClear", repl.clear, {})
