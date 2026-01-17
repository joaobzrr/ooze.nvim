local M = {}

---@param predicate fun(n: TSNode): boolean
---@return TSNode?
local function find_node(predicate)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local parser = vim.treesitter.get_parser(0)
	if not parser then
		return nil
	end
	local root = parser:parse()[1]:root()
	local node = root:named_descendant_for_range(cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2] + 1)
	while node do
		if predicate(node) then
			return node
		end
		node = node:parent()
	end
	return nil
end

function M.get_enclosing()
	local n = find_node(function(node)
		return node:type() == "list_lit"
	end)
	return n and vim.treesitter.get_node_text(n, 0)
end

function M.get_outermost()
	local n = find_node(function(node)
		local p = node:parent()
		return p and p:type() == "source"
	end)
	return n and vim.treesitter.get_node_text(n, 0)
end

function M.get_all()
	local parser = vim.treesitter.get_parser(0)
	if not parser then
		return nil
	end
	local root = parser:parse()[1]:root()
	local sexps = {}
	for node in root:iter_children() do
		if node:named() then
			table.insert(sexps, vim.treesitter.get_node_text(node, 0))
		end
	end
	return sexps
end

return M
