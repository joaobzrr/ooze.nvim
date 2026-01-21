local M = {}

function M.encode(tbl)
	local msg = vim.json.encode(tbl)
	return string.format("%06X%s", #msg, msg)
end

---@return table? result
---@return integer consumed
---@return string? err
function M.decode(buffer)
	if #buffer < 6 then
		return nil, 0, nil
	end

	local len = tonumber(buffer:sub(1, 6), 16)
	if not len then
		return nil, 0, "Invalid header"
	end

	local body = buffer:sub(7, 6 + len)
	local ok, result = pcall(vim.json.decode, body)
	if not ok then
		return nil, 0, "JSON decode error: " .. tostring(result)
	end

	return result, len + 6, nil
end

return M
