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

vim.api.nvim_create_autocmd("FileType", {
	pattern = "lisp",
	callback = function(args)
		local opts = { buffer = args.buf, silent = true }

		-- EVALUATION (Mnemonic: 'e')
		-- <leader>ee -> Eval Enclosing
		vim.keymap.set("n", "<leader>ee", ooze.eval_enclosing, opts)
		-- <leader>er -> Eval Root/Outermost
		vim.keymap.set("n", "<leader>er", ooze.eval_outermost, opts)
		-- <leader>eb -> Eval Buffer
		vim.keymap.set("n", "<leader>eb", ooze.eval_buffer, opts)

		-- REPL (Mnemonic: 'r')
		-- <leader>rt -> Repl Toggle
		vim.keymap.set("n", "<leader>rt", repl.toggle, opts)
		-- <leader>rc -> Repl Clear
		vim.keymap.set("n", "<leader>rc", repl.clear, opts)
	end,
})
