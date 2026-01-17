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

function M.get_enclosing_sexp()
	local n = find_node(function(node)
		return node:type() == "list_lit"
	end)
	return n and vim.treesitter.get_node_text(n, 0)
end

function M.get_outermost_sexp()
	local n = find_node(function(node)
		local p = node:parent()
		return p and p:type() == "source"
	end)
	return n and vim.treesitter.get_node_text(n, 0)
end

--Helper to check if a node intersects the given range
local function intersects(node, sr, sc, er, ec)
	local nsr, nsc, ner, nec = node:range()
	return not (ner < sr or (ner == sr and nec <= sc) or nsr > er or (nsr == er and nsc >= ec))
end

---Returns forms intersecting the selection: the smallest containing node if fully
---selected, otherwise its intersecting children.
---@param sr integer Start row (0-indexed)
---@param sc integer Start column
---@param er integer End row
---@param ec integer End column
---@return string[]
function M.get_selected_forms(sr, sc, er, ec)
	local parser = vim.treesitter.get_parser(0)
	if not parser then
		return {}
	end
	local root = parser:parse()[1]:root()

	local parent = root:named_descendant_for_range(sr, sc, er, ec)
	if not parent then
		return {}
	end

	local psr, psc, per, pec = parent:range()

	local is_full_node_selected = (sr < psr or (sr == psr and sc <= psc)) and (er > per or (er == per and ec >= pec))

	if is_full_node_selected then
		return { vim.treesitter.get_node_text(parent, 0) }
	end

	local forms = {}
	for child in parent:iter_children() do
		if child:named() and intersects(child, sr, sc, er, ec) then
			table.insert(forms, vim.treesitter.get_node_text(child, 0))
		end
	end

	return forms
end

function M.get_all_sexps()
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
