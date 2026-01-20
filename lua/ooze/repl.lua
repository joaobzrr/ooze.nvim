---@class Ooze.Repl
local M = {}

---@type Ooze.ReplState
local state = {
	buf = nil,
	win = nil,
	current_package = "CL-USER",
}

---@param fn fun()
local function modify_buf(fn)
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

	fn()

	if vim.fn.mode() ~= "i" then
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end
end

---@param lines string[]
function M.append(lines)
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	vim.schedule(function()
		modify_buf(function()
			local count = vim.api.nvim_buf_line_count(buf)
			local new_content = vim.list_extend({}, lines)
			vim.api.nvim_buf_set_lines(buf, count - 1, count, false, new_content)
		end)
	end)
end

local function create_buffer()
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.buf, "ooze://log")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.buf })
	vim.api.nvim_set_option_value("filetype", "lisp", { buf = state.buf })
	vim.api.nvim_set_option_value("undolevels", -1, { buf = state.buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
end

function M.open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		create_buffer()
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.cmd("botright 15split")
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf --[[@as integer]])
	end
end

---@param pkg string
function M.set_prompt_package(pkg)
	state.current_package = pkg:upper()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
end

function M.is_open()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
	if M.is_open() then
		vim.api.nvim_win_close(state.win --[[@as integer]], true)
		state.win = nil
	end
end

function M.cleanup()
	M.close()

	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		vim.api.nvim_buf_delete(state.buf, { force = true })
		state.buf = nil
	end
end

function M.clear()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	modify_buf(function()
		vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { "" })
	end)
end

return M
