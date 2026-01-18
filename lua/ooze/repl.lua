---@class Ooze.Repl
local M = {}

local dbg = require("core.debug")

---@type Ooze.ReplState
local state = {
	buf = nil,
	win = nil,
	current_package = "COMMON-LISP-USER",
	prompt_format = "%s> ",
	history = {},
	history_index = 0,
	on_submit = function() end,
}

-- Returns the start column of the valid insert range
local function get_insert_range_start_col()
	return #M.get_prompt_string()
end

-- Returns the end column of the valid insert range
local function get_insert_range_end_col()
	local last_line = vim.api.nvim_buf_get_lines(state.buf, -2, -1, false)[1] or ""
	return #last_line
end

-- Returns the start position of the valid insert range
---@return Ooze.Position
local function get_insert_range_start_position()
	local last_row = vim.api.nvim_buf_line_count(state.buf)
	local start_col = get_insert_range_start_col()
	return { last_row, start_col }
end

-- Returns the end position of the valid insert range
---@return Ooze.Position
local function get_insert_range_end_position()
	local line_count = vim.api.nvim_buf_line_count(state.buf)
	local end_col = get_insert_range_end_col()
	return { line_count, end_col }
end

---@param pos Ooze.Position
local function is_insert_position_valid(pos)
	local last_row = vim.api.nvim_buf_line_count(state.buf)
	local start_col = get_insert_range_start_col()
	return pos[1] == last_row and pos[2] >= start_col
end

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

local function submit()
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local last_line = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
	local min_col = get_insert_range_start_col()
	local code = last_line:sub(min_col + 1)

	modify_buf(function()
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
	end)

	if vim.trim(code) ~= "" then
		state.on_submit(code)
	else
		M.append({})
	end

	vim.api.nvim_win_set_cursor(0, get_insert_range_end_position())
end

---@param delta integer
local function navigate_history(delta)
	local new_idx = state.history_index + delta
	if new_idx < 1 or new_idx > #state.history + 1 then
		return
	end
	state.history_index = new_idx
	local content = state.history[state.history_index] or ""
	modify_buf(function()
		local buf_id = state.buf --[[@as integer]]
		local count = vim.api.nvim_buf_line_count(buf_id)
		local new_line = M.get_prompt_string() .. content
		vim.api.nvim_buf_set_lines(buf_id, count - 1, count, false, { new_line })
		vim.api.nvim_win_set_cursor(0, { count, #new_line })
	end)
end

---@param pos Ooze.Position
local function start_insert_at(pos)
	vim.cmd("startinsert")
	vim.api.nvim_win_set_cursor(0, pos)
end

---@param opts { on_submit: fun(code: string) }
function M.setup(opts)
	state.on_submit = opts.on_submit or state.on_submit
end

function M.get_prompt_string()
	return string.format(state.prompt_format, state.current_package)
end

---@param lines string[]
function M.append(lines)
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	modify_buf(function()
		local count = vim.api.nvim_buf_line_count(buf)
		local new_content = vim.list_extend({}, lines)
		table.insert(new_content, M.get_prompt_string())
		vim.api.nvim_buf_set_lines(buf, count - 1, count, false, new_content)
	end)
end

local function create_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	state.buf = buf

	vim.api.nvim_buf_set_name(buf, "ooze://repl")

	local buffer_options = { buftype = "nofile", filetype = "lisp", undolevels = -1, modifiable = false }
	for opt, val in pairs(buffer_options) do
		vim.api.nvim_set_option_value(opt, val, { buf = buf })
	end

	modify_buf(function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { M.get_prompt_string() })
	end)

	local opts = { buffer = buf, silent = true }

	for _, k in ipairs({ "i", "I", "a", "A", "o", "O" }) do
		vim.keymap.set("n", k, function()
			vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

			local cursor = vim.api.nvim_win_get_cursor(0)
			local original_row, original_col = cursor[1], cursor[2]

			local last_row = vim.api.nvim_buf_line_count(buf)

			local target_col
			if k == "a" or k == "A" then
				target_col = original_col + 1
			else
				target_col = original_col
			end

			if not is_insert_position_valid({ last_row, target_col }) then
				start_insert_at(get_insert_range_end_position())
			else
				start_insert_at({ original_row, target_col })
			end
		end, opts)
	end

	vim.keymap.set("i", "<CR>", submit, opts)

	vim.keymap.set("i", "<Up>", function()
		navigate_history(-1)
	end)

	vim.keymap.set("i", "<Down>", function()
		navigate_history(1)
	end)

	for _, key in ipairs({ "<BS>", "<S-BS>", "<C-BS>", "<C-h>" }) do
		vim.keymap.set("i", key, function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			return cursor[2] <= get_insert_range_start_col() and "" or "<BS>"
		end, { buffer = buf, expr = true })
	end

	vim.keymap.set("i", "<C-u>", function()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local min_col = get_insert_range_start_col()
		if cursor[2] > min_col then
			vim.api.nvim_buf_set_text(buf, cursor[1] - 1, min_col, cursor[1] - 1, cursor[2], {})
		end
	end, opts)

	-- Lock everything else
	for _, k in ipairs({ "dd", "cc", "S", "D", "C", "x", "X", "p", "P", "<Del>", "r", "R" }) do
		vim.keymap.set({ "n", "v" }, k, function() end, opts)
	end

	local group = vim.api.nvim_create_augroup("OozeReplGuard_" .. buf, { clear = true })
	vim.api.nvim_create_autocmd({ "InsertLeave", "CursorMovedI" }, {
		buffer = buf,
		group = group,
		callback = function()
			if not is_insert_position_valid(vim.api.nvim_win_get_cursor(0)) then
				vim.api.nvim_win_set_cursor(0, get_insert_range_start_position())
			end

			if vim.fn.mode() ~= "i" then
				vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
			end
		end,
	})
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

	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })

	vim.cmd("startinsert!")
end

---@param pkg string
function M.set_prompt_package(pkg)
	state.current_package = pkg:upper()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	modify_buf(function()
		local buf = state.buf --[[@as integer]]
		local count = vim.api.nvim_buf_line_count(buf)
		local last = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
		if last:match("^[^>]+> *$") then
			vim.api.nvim_buf_set_lines(buf, count - 1, count, false, { M.get_prompt_string() })
		end
	end)
end

---@param commands string | string[]
function M.add_history(commands)
	---@type string[]
	local command_list = type(commands) == "table" and commands or { commands }

	for _, v in ipairs(command_list) do
		if vim.trim(v) ~= "" then
			table.insert(state.history, v)
		end
	end
	state.history_index = #state.history + 1
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

	state.history = {}
	state.history_index = 0
end

function M.clear()
	if state.buf then
		modify_buf(function()
			vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { M.get_prompt_string() })
		end)
	end
end

return M
