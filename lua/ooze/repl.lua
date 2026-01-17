local M = {}

---@class Ooze.ReplState
local state = {
	buf = nil,
	win = nil,
	prompt = "OOZE> ",
}

---@param lines string[]
function M.append(lines)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local row = vim.api.nvim_buf_line_count(state.buf)
	vim.api.nvim_buf_set_lines(state.buf, row - 1, row - 1, false, lines)

    vim.api.nvim_set_option_value("modified", false, { buf = state.buf })

	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
	end
end

function M.open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.buf, "ooze://repl")
		vim.api.nvim_set_option_value("buftype", "prompt", { buf = state.buf })
		vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
		vim.api.nvim_set_option_value("buflisted", false, { buf = state.buf })
        vim.api.nvim_set_option_value("modified", false, { buf = state.buf })
		vim.api.nvim_set_option_value("filetype", "lisp", { buf = state.buf })
		vim.fn.prompt_setprompt(state.buf, state.prompt)
		vim.fn.prompt_setcallback(state.buf, function(text)
			if text:gsub("%s+", "") ~= "" then
				require("ooze").eval(text, { silent = true })
			end
		end)
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.cmd("botright 15split")
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
		vim.api.nvim_set_option_value("number", false, { win = state.win })
		vim.api.nvim_set_option_value("relativenumber", false, { win = state.win })
		vim.api.nvim_set_option_value("signcolumn", "no", { win = state.win })
	end

	vim.cmd("startinsert")
end

---@return boolean
function M.is_open()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return M
