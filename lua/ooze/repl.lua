---@class Ooze.Repl
local M = {}

---@type Ooze.ReplState
local state = {
	buf = nil,
	win = nil,
	current_package = "COMMON-LISP-USER",
	prompt_format = "%s> ",
	history = {},
	history_index = 0,
}

function M.get_prompt_string()
	return string.format(state.prompt_format, state.current_package)
end

-- Returns the minimum valid cursor column (right after the prompt and its trailing space)
local function get_min_valid_col()
	return #M.get_prompt_string()
end

---@return boolean isValid True if cursor is in the valid typing zone
---@return integer currentLine
---@return integer currentCol
local function get_zone_info()
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return false, 0, 0
	end
	local cursor = vim.api.nvim_win_get_cursor(state.win)
	local line_count = vim.api.nvim_buf_line_count(state.buf)
	local min_col = get_min_valid_col()
	-- Valid if on the last line AND cursor is strictly after the prompt (not on the space)
	return (cursor[1] == line_count and cursor[2] > min_col), cursor[1], cursor[2]
end

-- Snap cursor to the end of the last line
local function snap_to_end()
	local line_count = vim.api.nvim_buf_line_count(state.buf)
	local last_line = vim.api.nvim_buf_get_lines(state.buf, -2, -1, false)[1] or ""
	vim.api.nvim_win_set_cursor(state.win, { line_count, #last_line })
end

local function modify_buf(fn)
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	fn()
	-- Only lock if we aren't in the middle of typing in the active zone
	if vim.fn.mode() ~= "i" then
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end
end

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
		vim.api.nvim_buf_set_lines(buf_id, count - 1, count, false, { M.get_prompt_string() .. content })
		snap_to_end()
	end)
end

local function submit()
	local buf = state.buf
	local last_line = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
	local min_col = get_min_valid_col()

	-- Grab everything AFTER the prompt (including trailing space)
	local code = last_line:sub(min_col + 1)

	modify_buf(function()
		-- Add a newline to finalize the entry
		vim.api.nvim_buf_set_lines(buf, vim.api.nvim_buf_line_count(buf), -1, false, { "" })
	end)

	if vim.trim(code) ~= "" then
		-- This calls ooze.eval, which will eventually call repl.append
		require("ooze").eval(code, { echo = false })
	else
		M.append({}) -- Just print a new prompt
	end
end

function M.append(lines)
	local buf = state.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.schedule(function()
		modify_buf(function()
			local count = vim.api.nvim_buf_line_count(buf)
			local new_content = vim.list_extend({}, lines)
			table.insert(new_content, M.get_prompt_string())
			-- Replace the "dead" prompt line with output + new prompt
			vim.api.nvim_buf_set_lines(buf, count - 1, count, false, new_content)
		end)
		snap_to_end()
		vim.cmd("redraw")
	end)
end

local function setup_buffer_protection(buf)
	local opts = { buffer = buf, silent = true }

	-- Normal mode entry: Check if resulting insert position will be valid
	for _, k in ipairs({ "i", "I", "a", "A", "o", "O" }) do
		vim.keymap.set("n", k, function()
			vim.api.nvim_set_option_value("modifiable", true, { buf = buf })

			local cursor = vim.api.nvim_win_get_cursor(0)
			local line_count = vim.api.nvim_buf_line_count(buf)
			local min_col = get_min_valid_col()
			local current_col = cursor[2]

			-- Calculate what the cursor column will be in insert mode
			local resulting_col
			if k == "a" or k == "A" then
				resulting_col = current_col + 1 -- 'a' moves one position right
			else
				resulting_col = current_col -- 'i' stays in place
			end

			-- Check if resulting position will be valid (must be strictly after the prompt)
			-- We allow cursor to be anywhere from min_col onwards (including past end of line)
			local will_be_valid = (cursor[1] == line_count and resulting_col > min_col)

			if not will_be_valid then
				-- Resulting position would be invalid, snap to end
				snap_to_end()
				vim.cmd("startinsert!")
			else
				-- Resulting position will be valid
				if k == "a" or k == "A" then
					-- Move cursor one position right, then enter insert mode
					vim.api.nvim_win_set_cursor(0, { cursor[1], resulting_col })
					vim.cmd("startinsert")
				else
					-- 'i' stays in place
					vim.cmd("startinsert")
				end
			end
		end, opts)
	end

	vim.keymap.set("i", "<CR>", submit, opts)

	-- Backspace protection: Don't delete the prompt or its trailing space
	vim.keymap.set("i", "<BS>", function()
		local _, _, col = get_zone_info()
		return col <= get_min_valid_col() and "" or "<BS>"
	end, { buffer = buf, expr = true })

	-- CTRL+U protection: Delete only up to the prompt
	vim.keymap.set("i", "<C-u>", function()
		local cursor = vim.api.nvim_win_get_cursor(0)
		local min_col = get_min_valid_col()
		if cursor[2] > min_col then
			-- Delete from min_col to current cursor position
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
			local valid = get_zone_info()
			if not valid then
				-- Move to first valid typing position (right after the prompt space)
				local line_count = vim.api.nvim_buf_line_count(buf)
				local min_col = get_min_valid_col()
				vim.api.nvim_win_set_cursor(0, { line_count, min_col + 1 })
			end
			if vim.fn.mode() ~= "i" then
				vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
			end
		end,
	})
end

function M.open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.buf, "ooze://repl")
		local props = { buftype = "nofile", filetype = "lisp", undolevels = -1, modifiable = false }
		for opt, val in pairs(props) do
			vim.api.nvim_set_option_value(opt, val, { buf = state.buf })
		end
		modify_buf(function()
			vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { M.get_prompt_string() })
		end)
		setup_buffer_protection(state.buf)
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.cmd("botright 15split")
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf --[[@as integer]])
	end

	require("ooze").sync_state()
	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
	snap_to_end()
	vim.cmd("startinsert!")
end

function M.set_prompt_package(pkg)
	state.current_package = pkg:upper()
	if state.buf then
		modify_buf(function()
			local buf = state.buf --[[@as integer]]
			local count = vim.api.nvim_buf_line_count(buf)
			local last = vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] or ""
			if last:match("^[^>]+> *$") then
				vim.api.nvim_buf_set_lines(buf, count - 1, count, false, { M.get_prompt_string() })
			end
		end)
	end
end

function M.add_history(c)
	for _, v in ipairs(type(c) == "table" and c or { c }) do
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
			vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { M.get_prompt_string() })
		end)
		snap_to_end()
	end
end

return M
