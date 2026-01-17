local M = {}

---@class Ooze.ReplState
local state = {
	buf = nil,
	win = nil,
	prompt = "OOZE> ",
	history = {},
	history_index = 0,
}

---Adds a string (or multiple) to the command history.
---@param input string | string[]
function M.add_to_history(input)
	local items = type(input) == "table" and input or { input }
	for _, item in ipairs(items) do
		local trimmed = vim.trim(item)
		-- Don't add if empty or duplicate of the last entry
		if trimmed ~= "" and state.history[#state.history] ~= trimmed then
			table.insert(state.history, trimmed)
		end
	end
	state.history_index = #state.history + 1
end

---Cycles through history in the prompt buffer without scrolling.
---@param direction 1 | -1
local function cycle_history(direction)
	if #state.history == 0 then
		return
	end

	local new_index = state.history_index + direction
	if new_index < 1 then
		new_index = 1
	elseif new_index > #state.history then
		new_index = #state.history + 1
	end

	state.history_index = new_index
	local text = state.history[new_index] or ""

	-- We use <C-u> to clear the current prompt line and insert the history text.
	-- This avoids standard line navigation which causes scrolling.
	local keys = vim.api.nvim_replace_termcodes("<C-u>" .. text, true, false, true)
	vim.api.nvim_feedkeys(keys, "n", false)
end

---Appends lines to the REPL buffer efficiently.
---@param lines string[]
function M.append(lines)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local last_line = vim.api.nvim_buf_line_count(state.buf)

	vim.api.nvim_buf_set_lines(state.buf, last_line - 1, last_line - 1, false, lines)
	vim.api.nvim_set_option_value("modified", false, { buf = state.buf })
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		local new_last_line = vim.api.nvim_buf_line_count(state.buf)
		vim.api.nvim_win_set_cursor(state.win, { new_last_line, 0 })
	end
end

function M.clear()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
	-- Prompt buffers require at least one line (the prompt)
	-- We clear everything and the prompt_setprompt/callback handles the rest
	vim.api.nvim_buf_set_lines(state.buf, 0, -2, false, {})
	vim.api.nvim_set_option_value("modified", false, { buf = state.buf })
end

function M.open()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.buf, "ooze://repl")

		vim.api.nvim_set_option_value("buftype", "prompt", { buf = state.buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
		vim.api.nvim_set_option_value("buflisted", false, { buf = state.buf })
		vim.api.nvim_set_option_value("filetype", "lisp", { buf = state.buf })

		vim.fn.prompt_setprompt(state.buf, state.prompt)
		vim.fn.prompt_setcallback(state.buf, function(text)
			if vim.trim(text) ~= "" then
				require("ooze").eval(text, { silent = true })
			end
			vim.api.nvim_set_option_value("modified", false, { buf = state.buf })
		end)

		local opts = { buffer = state.buf, silent = true }

		vim.keymap.set("i", "<Up>", function()
			cycle_history(-1)
		end, opts)
		vim.keymap.set("i", "<C-p>", function()
			cycle_history(-1)
		end, opts)
		vim.keymap.set("i", "<Down>", function()
			cycle_history(1)
		end, opts)
		vim.keymap.set("i", "<C-n>", function()
			cycle_history(1)
		end, opts)
	end

	if not state.win or not vim.api.nvim_win_is_valid(state.win) then
		vim.cmd("botright 15split")
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)

		-- Window styling
		vim.api.nvim_set_option_value("number", false, { win = state.win })
		vim.api.nvim_set_option_value("relativenumber", false, { win = state.win })
		vim.api.nvim_set_option_value("signcolumn", "no", { win = state.win })
		-- Ensure scrolling behavior is consistent
		vim.api.nvim_set_option_value("scrolloff", 0, { win = state.win })
	end

	vim.cmd("startinsert")
end

function M.close()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
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

---@return boolean
function M.is_open()
	return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

return M
