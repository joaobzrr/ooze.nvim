---@module 'ooze.plugin'

if vim.g.loaded_ooze then
	return
end
vim.g.loaded_ooze = true

-- This file is loaded by Neovim at startup and is the place
-- to create user commands and keymaps.

---@diagnostic disable-next-line: missing-fields
---@type Ooze
local ooze = require("ooze")

vim.api.nvim_create_user_command(
	"OozeEval",
	---@param opts table @ The command options (nargs, fargs, etc. based on vim.api.nvim_create_user_command)
	function(opts)
		ooze.eval_current_line()
	end,
	{
		nargs = 0,
		desc = "Evaluate the current Lisp line.",
	}
)

