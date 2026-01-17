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

---Teleports the cursor to the very end of the buffer (the editable line)
local function snap_to_prompt()
	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		return
	end
	local line_count = vim.api.nvim_buf_line_count(state.buf)
	local last_line = vim.api.nvim_buf_get_lines(state.buf, -2, -1, false)[1] or ""
	vim.api.nvim_win_set_cursor(state.win, { line_count, #last_line })
end

---Safely toggles modifiable to update REPL contents
local function modify_buf(fn)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
	fn()
	if vim.api.nvim_get_current_buf() ~= state.buf or vim.fn.mode() ~= "i" then
		vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
	end
end

---Replaces the current input line with an entry from history
local function navigate_history(delta)
	local new_idx = state.history_index + delta
	if new_idx < 1 or new_idx > #state.history + 1 then
		return
	end

	state.history_index = new_idx
	local content = state.history[state.history_index] or ""

	modify_buf(function()
		local count = vim.api.nvim_buf_line_count(state.buf)
		vim.api.nvim_buf_set_lines(state.buf, count - 1, count, false, { M.get_prompt_string() .. content })
		snap_to_prompt()
	end)
end

---Sends the text after the prompt to the Lisp server
local function submit()
	local line_count = vim.api.nvim_buf_line_count(state.buf)
	local last_line = vim.api.nvim_buf_get_lines(state.buf, -2, -1, false)[1] or ""
	local prompt_str = M.get_prompt_string()
	local code = last_line:sub(#prompt_str + 1)

	modify_buf(function()
		vim.api.nvim_buf_set_lines(state.buf, line_count, line_count, false, { "" })
	end)

	if vim.trim(code) ~= "" then
		require("ooze").eval(code, { echo = false })
	else
		M.append({})
	end
end

function M.append(lines)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	vim.schedule(function()
		modify_buf(function()
			local count = vim.api.nvim_buf_line_count(state.buf)
			local new_content = {}
			for _, l in ipairs(lines) do
				table.insert(new_content, l)
			end
			table.insert(new_content, M.get_prompt_string())
			vim.api.nvim_buf_set_lines(state.buf, count - 1, count, false, new_content)
		end)
		snap_to_prompt()
		vim.cmd("redraw")
	end)
end

function M.open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.buf, "ooze://repl")

		local buf = state.buf
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("filetype", "lisp", { buf = buf })
		vim.api.nvim_set_option_value("undolevels", -1, { buf = buf })
		vim.api.nvim_set_option_value("omnifunc", "", { buf = buf })
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

		modify_buf(function()
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { M.get_prompt_string() })
		end)

		local opts = { buffer = buf, silent = true }

		local insert_keys = { "i", "I", "a", "A", "o", "O" }
		for _, k in ipairs(insert_keys) do
			vim.keymap.set("n", k, function()
				vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
				snap_to_prompt()
				vim.cmd("startinsert!")
			end, opts)
		end

		vim.keymap.set("i", "<CR>", submit, opts)
		vim.keymap.set("i", "<C-p>", function()
			navigate_history(-1)
		end, opts)
		vim.keymap.set("i", "<C-n>", function()
			navigate_history(1)
		end, opts)

		vim.keymap.set("i", "<BS>", function()
			local col = vim.api.nvim_win_get_cursor(0)[2]
			return col <= #M.get_prompt_string() and "" or "<BS>"
		end, { buffer = buf, expr = true })

		vim.keymap.set("i", "<C-u>", function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local prompt_len = #M.get_prompt_string()
			if cursor[2] > prompt_len then
				-- Delete from prompt_len to current cursor position
				vim.api.nvim_buf_set_text(buf, cursor[1] - 1, prompt_len, cursor[1] - 1, cursor[2], {})
			end
		end, opts)

		vim.keymap.set("i", "<C-w>", function()
			local col = vim.api.nvim_win_get_cursor(0)[2]
			local prompt_len = #M.get_prompt_string()
			if col <= prompt_len then
				return
			end
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-w>", true, false, true), "n", false)
		end, opts)

		vim.keymap.set("i", "<Del>", function()
			local col = vim.api.nvim_win_get_cursor(0)[2]
			return col < #M.get_prompt_string() and "" or "<Del>"
		end, { buffer = buf, expr = true })

		local locks = { "dd", "cc", "S", "D", "C", "x", "X", "p", "P", "<Del>", "r", "R" }
		for _, k in ipairs(locks) do
			vim.keymap.set({ "n", "v" }, k, function() end, opts)
		end

		vim.api.nvim_create_autocmd("InsertLeave", {
			buffer = buf,
			callback = function()
				vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
			end,
		})

		vim.api.nvim_create_autocmd("CursorMovedI", {
			buffer = buf,
			callback = function()
				local cursor = vim.api.nvim_win_get_cursor(0)
				local prompt_len = #M.get_prompt_string()
				if cursor[2] < prompt_len then
					vim.api.nvim_win_set_cursor(0, { cursor[1], prompt_len })
				end
			end,
		})
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.cmd("botright 15split")
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
	end

	require("ooze").sync_state()
	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
	snap_to_prompt()
	vim.cmd("startinsert!")
end

function M.set_prompt_package(pkg_name)
	state.current_package = pkg_name:upper()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		modify_buf(function()
			local count = vim.api.nvim_buf_line_count(state.buf)
			local last_line = vim.api.nvim_buf_get_lines(state.buf, -2, -1, false)[1] or ""
			local new_prompt = M.get_prompt_string()
			if last_line:match("^[^>]+> *$") then
				vim.api.nvim_buf_set_lines(state.buf, count - 1, count, false, { new_prompt })
			end
		end)
	end
end

function M.add_history(c)
	local t = type(c) == "table" and c or { c }
	for _, v in ipairs(t) do
		local trimmed = vim.trim(v)
		if trimmed ~= "" then
			table.insert(state.history, trimmed)
		end
	end
	state.history_index = #state.history + 1
end

function M.is_open()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
	if M.is_open() then
		vim.api.nvim_win_close(state.win, true)
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
		snap_to_prompt()
	end
end

return M
