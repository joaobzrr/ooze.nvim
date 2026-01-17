local uv = vim.uv
local M = {}

---@class Ooze.RpcInternalState
---@field client uv.uv_tcp_t?
---@field buffer string
---@field callbacks table<integer, fun(res: Ooze.RpcResponse)>
---@field next_id integer
local state = {
	client = nil,
	buffer = "",
	callbacks = {},
	next_id = 1,
}

---@param data table
---@param cb fun(res: Ooze.RpcResponse)?
function M.send_request(data, cb)
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
	local frame = string.format("%06X%s", #msg, msg)
	state.client:write(frame)
end

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
				if not len or #state.buffer < 6 + len then
					return
				end

				local body = state.buffer:sub(7, 6 + len)
				state.buffer = state.buffer:sub(6 + len + 1)

				local ok, parsed = pcall(vim.json.decode, body)
				if ok and parsed.id and state.callbacks[parsed.id] then
					local callback = state.callbacks[parsed.id]
					state.callbacks[parsed.id] = nil
					vim.schedule(function()
						callback(parsed)
					end)
				end
			end
		end)
	end)
end

---@param sexps string[]
---@param cb fun(res: Ooze.RpcResponse)
function M.eval(sexps, cb)
	-- Update this to use the now-exported function
	M.send_request({ op = "eval", code = sexps }, cb)
end

return M
