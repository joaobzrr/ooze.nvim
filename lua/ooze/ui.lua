local M = {}

---@param result Ooze.EvalResult
---@return string[]
function M.format_eval_result(result)
	local lines = {}
	if result.stdout and result.stdout ~= "" then
		for _, l in ipairs(vim.split(result.stdout, "\n")) do
			if l ~= "" then
				table.insert(lines, ";; " .. l)
			end
		end
	end

	if result.ok then
		table.insert(lines, ";; " .. (result.value or "nil"))
	else
		local err_lines = vim.split(result.err or "Unknown Error", "\n")
		for i, l in ipairs(err_lines) do
			table.insert(lines, (i == 1 and ";; ERROR: " or ";; ") .. l)
		end
	end
	return lines
end

---@param code string
---@param prompt string
---@return string[]
function M.format_echo(code, prompt)
	local lines = {}
	local code_lines = vim.split(code, "\n")
	local indent = string.rep(" ", #prompt)
	for i, line in ipairs(code_lines) do
		table.insert(lines, (i == 1 and prompt or indent) .. line)
	end
	return lines
end

return M
