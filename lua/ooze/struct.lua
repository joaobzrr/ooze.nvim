---@module 'ooze.struct'
local M = {}

---Parses a JSON string into a Lua table.
---@param body string The JSON string to parse.
---@return table result
function M.parse(body)
	-- The pcall has been moved to the caller in rpc.lua.
	-- This function now directly returns the decoded table, or errors.
	return vim.json.decode(body)
end

---Serializes a Lua table into a JSON string.
---@param tbl table The Lua table to serialize.
---@return string? json_string
function M.serialize(tbl)
	return vim.json.encode(tbl)
end

return M
