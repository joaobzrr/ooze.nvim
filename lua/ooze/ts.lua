---@module 'ooze.ts'
---@class OozeTs
local M = {}

---@private
---@param predicate fun(node: TSNode): boolean
---@return TSNode?
local function find_sexp_from_cursor(predicate)
    local buf = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]

    local parser = vim.treesitter.get_parser(buf)
    if not parser then
        return nil
    end

    local tree = parser:parse()[1]
    if not tree then
        return nil
    end

    local root = tree:root()
    if not root then
        return nil
    end

    local node = root:named_descendant_for_range(row, col, row, col + 1)
    if not node then
        return nil
    end

    local last_match = nil

    while node do
        if predicate(node) then
            last_match = node
            break
        end
        node = node:parent()
    end

    return last_match
end

--- Finds the nearest enclosing form.
---@return string? The text of the form, or nil if not found.
function M.get_enclosing_sexp_at_cursor()
    local node = find_sexp_from_cursor(function(n)
        return n:type() == "list_lit"
    end)

    return node and vim.treesitter.get_node_text(node, 0) or nil
end

--- Finds the outermost Lisp form containing the cursor.
---@return string?
function M.get_outermost_sexp_at_cursor()
    local node = find_sexp_from_cursor(function(n)
        local parent = n:parent()
        return parent ~= nil and parent:type() == "source"
    end)

    return node and vim.treesitter.get_node_text(node, 0) or nil
end

---@return string[]?
function M.get_toplevel_sexps_in_buffer()
    local buf = vim.api.nvim_get_current_buf()

    local parser = vim.treesitter.get_parser(buf)
    if not parser then
        return nil
    end

    local tree = parser:parse()[1]

    local root = tree:root()
    local sexps = {}

    for node in root:iter_children() do
        if node:named() then
            table.insert(sexps, vim.treesitter.get_node_text(node, buf))
        end
    end
    return sexps
end

return M
