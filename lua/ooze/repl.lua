local ui = require("ooze.ui")

---@class Ooze.Repl
local M = {}

---@class Ooze.ReplState
---@field buf integer? The REPL buffer handle
---@field win integer? The REPL window handle
---@field current_package string The current Lisp package
---@field prompt_format string Format string for the prompt
---@field history string[] List of submitted commands
---@field history_index integer Current position in history navigation
local state = {
	buf = nil,
	win = nil,
	current_package = "COMMON-LISP-USER",
	prompt_format = "%s> ",
	history = {},
	history_index = 0,
}

---@return string
function M.get_prompt_string()
	return string.format(state.prompt_format, state.current_package)
end

---@return integer # The length of the current prompt string
local function get_prompt_len()
	return #M.get_prompt_string()
end

---Teleports the cursor to the very end of the buffer (the editable line)
local function snap_to_prompt()
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local buf = state.buf --[[@as integer]]
	local line_count = vim.api.nvim_buf_line_count(buf)
	local last_line = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
	vim.api.nvim_win_set_cursor(state.win, { line_count, #last_line })
end

---Safely toggles modifiable to update REPL contents
---@param fn fun()
local function modify_buf(fn)
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	fn()
	-- Lock if we aren't in active insert mode in this buffer
	if vim.api.nvim_get_current_buf() ~= buf or vim.fn.mode() ~= "i" then
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end
end

---Navigates history by a delta
---@param delta integer
local function navigate_history(delta)
	local new_idx = state.history_index + delta
	if new_idx < 1 or new_idx > #state.history + 1 then
		return
	end

	state.history_index = new_idx
	local content = state.history[state.history_index] or ""

	modify_buf(function()
		local count = vim.api.nvim_buf_line_count(state.buf --[[@as integer]])
		vim.api.nvim_buf_set_lines(
			state.buf --[[@as integer]],
			count - 1,
			count,
			false,
			{ M.get_prompt_string() .. content }
		)
		snap_to_prompt()
	end)
end

---Sends the text after the prompt to the Lisp server
local function submit()
	local buf = state.buf --[[@as integer]]
	local line_count = vim.api.nvim_buf_line_count(buf)
	local last_line = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
	local prompt_str = M.get_prompt_string()
	local code = last_line:sub(#prompt_str + 1)

	modify_buf(function()
		vim.api.nvim_buf_set_lines(buf, line_count, line_count, false, { "" })
	end)

	if vim.trim(code) ~= "" then
		require("ooze").eval(code, { echo = false })
	else
		M.append({})
	end
end

---Append lines to the REPL buffer
---@param lines string[]
function M.append(lines)
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.schedule(function()
		modify_buf(function()
			local count = vim.api.nvim_buf_line_count(buf)
			local new_content = {}
			for _, l in ipairs(lines) do
				table.insert(new_content, l)
			end
			table.insert(new_content, M.get_prompt_string())
			vim.api.nvim_buf_set_lines(buf, count - 1, count, false, new_content)
		end)
		snap_to_prompt()
		vim.cmd("redraw")
	end)
end

---Sets up buffer-local keymaps and autocmds
---@param buf integer
local function setup_buffer_protection(buf)
	local opts = { buffer = buf, silent = true }

	-- 1. Normal Mode Hijack (Entry)
	local insert_keys = { "i", "I", "a", "A", "o", "O" }
	for _, k in ipairs(insert_keys) do
		vim.keymap.set("n", k, function()
			vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
			snap_to_prompt()
			vim.cmd("startinsert!")
		end, opts)
	end

	-- 2. Insert Mode Mappings
	vim.keymap.set("i", "<CR>", submit, opts)
	vim.keymap.set("i", "<C-p>", function()
		navigate_history(-1)
	end, opts)
	vim.keymap.set("i", "<C-n>", function()
		navigate_history(1)
	end, opts)

	vim.keymap.set("i", "<BS>", function()
		local col = vim.api.nvim_win_get_cursor(0)[2]
		return col <= get_prompt_len() and "" or "<BS>"
	end, { buffer = buf, expr = true })

	vim.keymap.set("i", "<C-u>", function()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local plen = get_prompt_len()
		if cursor[2] > plen then
			vim.api.nvim_buf_set_text(buf, cursor[1] - 1, plen, cursor[1] - 1, cursor[2], {})
		end
	end, opts)

	vim.keymap.set("i", "<C-w>", function()
		if vim.api.nvim_win_get_cursor(0)[2] <= get_prompt_len() then
			return
		end
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>", true, false, true), "n", false)
	end, opts)

	vim.keymap.set("i", "<Del>", function()
		return vim.api.nvim_win_get_cursor(0)[2] < get_prompt_len() and "" or "<Del>"
	end, { buffer = buf, expr = true })

	-- 3. Locking History
	local locks = { "dd", "cc", "S", "D", "C", "x", "X", "p", "P", "<Del>", "r", "R" }
	for _, k in ipairs(locks) do
		vim.keymap.set({ "n", "v" }, k, function() end, opts)
	end

	-- 4. Elasticity Autocmds
	local group = vim.api.nvim_create_augroup("OozeReplGuard_" .. buf, { clear = true })

	vim.api.nvim_create_autocmd("InsertLeave", {
		buffer = buf,
		group = group,
		callback = function()
			vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		end,
	})

	vim.api.nvim_create_autocmd("CursorMovedI", {
		buffer = buf,
		group = group,
		callback = function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local plen = get_prompt_len()
			if cursor[2] < plen then
				vim.api.nvim_win_set_cursor(0, { cursor[1], plen })
			end
		end,
	})
end

---Open the REPL window
function M.open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.buf, "ooze://repl")

		local buf = state.buf
		local props = {
			buftype = "nofile",
			filetype = "lisp",
			undolevels = -1,
			omnifunc = "",
			modifiable = false,
		}
		for opt, val in pairs(props) do
			vim.api.nvim_set_option_value(opt, val, { buf = buf })
		end

		modify_buf(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { M.get_prompt_string() })
		end)

		setup_buffer_protection(buf)
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.cmd("botright 15split")
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf --[[@as integer]])
	end

	require("ooze").sync_state()
	vim.api.nvim_set_option_value("modifiable", true, {
		buf = state.buf --[[@as integer]],
	})
	snap_to_prompt()
	vim.cmd("startinsert!")
end

---Update the prompt based on the current Lisp package
---@param pkg_name string
function M.set_prompt_package(pkg_name)
	state.current_package = pkg_name:upper()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		modify_buf(function()
			local buf = state.buf --[[@as integer]]
			local count = vim.api.nvim_buf_line_count(buf)
			local last_line = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
			local new_prompt = M.get_prompt_string()
			if last_line:match("^[^>]+> *$") then
				vim.api.nvim_buf_set_lines(buf, count - 1, count, false, { new_prompt })
			end
		end)
	end
end

---Add code to the command history
---@param c string|string[]
function M.add_history(c)
	local entries = type(c) == "table" and c or { c }
	for _, v in ipairs(entries) do
		local trimmed = vim.trim(v)
		if trimmed ~= "" then
			table.insert(state.history, trimmed)
		end
	end
	state.history_index = #state.history + 1
end

---@return boolean
function M.is_open()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
	if M.is_open() then
		vim.api.nvim_win_close(state.win --[[@as integer]], true)
		state.win = nil
	end
end

function M.toggle()
	if M.is_open() then
		M.close()
	else
		M.open()
	end
end

function M.clear()
	if state.buf then
		modify_buf(function()
			vim.api.nvim_buf_set_lines(state.buf --[[@as integer]], 0, -1, false, { M.get_prompt_string() })
		end)
		snap_to_prompt()
	end
end

return M
