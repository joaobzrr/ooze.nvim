---@module 'ooze.repl'

local ooze = require("ooze")

local M = {}

---@class OozeReplState
---@field buf? integer The buffer handle for the REPL.
---@field win? integer The window handle for the REPL.
---@field prompt string The string displayed at the prompt.
---@field history string[] A list of commands entered by the user.
---@field history_idx integer The current position in the history for navigation.
local state = {
	buf = nil,
	win = nil,
	prompt = "OOZE> ",
	history = {},
	history_idx = 0,
}

---The callback executed when the user presses Enter in the REPL.
---This function is public because it must be accessible via `v:lua`.
---@param text string The text entered by the user.
function M.on_enter(text)
	if text == "" then
		return
	end

	-- We don't manually append the prompt+text here anymore because
	-- either the prompt buffer shows it, or we want the central display logic to handle it.
	-- To get the behavior you want:
	ooze.eval(text, { silent = true })
end

---@private
---Creates and configures the REPL buffer.
---@return integer buf The buffer handle.
local function create_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "ooze://repl")
	vim.api.nvim_set_option_value("buftype", "prompt", { buf = buf })
	vim.api.nvim_set_option_value("filetype", "lisp", { buf = buf })
	vim.fn.prompt_setprompt(buf, state.prompt)
	vim.fn.prompt_setcallback(buf, M.on_enter)
	return buf
end

function M.append_output(text)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local lines = type(text) == "table" and text or vim.split(tostring(text), "\n")
	local line_count = vim.api.nvim_buf_line_count(state.buf)
	vim.api.nvim_buf_set_lines(state.buf, line_count - 1, line_count - 1, false, lines)

	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_set_cursor(state.win, { vim.api.nvim_buf_line_count(state.buf), 0 })
	end
end

---Opens the REPL window.
function M.open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = create_buffer()
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.cmd("botright 15split")
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
	else
		vim.api.nvim_set_current_win(state.win)
	end

	vim.cmd("startinsert")
end

---Toggles the visibility of the REPL window.
function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

---Returns true if the REPL window is currently open and valid.
---@return boolean?
function M.is_open()
	return state.win and vim.api.nvim_win_is_valid(state.win)
end

return M
