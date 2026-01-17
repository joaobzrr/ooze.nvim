local uv = vim.uv

local M = {}

---@class Ooze.RpcState
local state = {
	client = nil, ---@type uv.uv_tcp_t?
	buffer = "",
	callbacks = {}, ---@type table<integer, fun(res: Ooze.RpcResponse)>
	next_id = 1,
}

---@param host string
---@param port integer
function M.connect(host, port)
	if state.client then
		return
	end
	state.client = uv.new_tcp()

	state.client:connect(host, port, function(err)
		if err then
			state.client = nil
			return
		end

		state.client:read_start(function(read_err, data)
			if read_err or not data then
				return
			end
			state.buffer = state.buffer .. data

			while #state.buffer >= 6 do
				local len = tonumber(state.buffer:sub(1, 6), 16)
				if not len or #state.buffer < (6 + len) then
					break
				end

				local body = state.buffer:sub(7, 6 + len)
				state.buffer = state.buffer:sub(6 + len + 1)

				local ok, parsed = pcall(vim.json.decode, body)
				if ok and parsed.id and state.callbacks[parsed.id] then
					local cb = state.callbacks[parsed.id]
					state.callbacks[parsed.id] = nil
					vim.schedule(function()
						cb(parsed)
					end)
				end
			end
		end)
	end)
end

---@param data table
---@param cb? fun(res: Ooze.RpcResponse)
function M.send(data, cb)
	if not state.client or state.client:is_closing() then
		if cb then
			cb({ id = -1, ok = false, err = "Disconnected" })
		end
		return
	end

	local id = state.next_id
	state.next_id = id + 1
	if cb then
		state.callbacks[id] = cb
	end

	data.id = id
	local msg = vim.json.encode(data)
	state.client:write(string.format("%06X%s", #msg, msg))
end

return M
