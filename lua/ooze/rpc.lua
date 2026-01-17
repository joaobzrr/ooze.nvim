local uv = vim.uv

local M = {}

local state = {
	client = nil,
	buffer = {},
	callbacks = {},
	next_id = 1,
}

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
			table.insert(state.buffer, data)
			local chunk = table.concat(state.buffer)

			while #chunk >= 6 do
				local len = tonumber(chunk:sub(1, 6), 16)
				if not len or #chunk < (6 + len) then
					break
				end

				local body = chunk:sub(7, 6 + len)
				chunk = chunk:sub(6 + len + 1)
				state.buffer = { chunk } -- Reset buffer with remaining

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
