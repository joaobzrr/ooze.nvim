local uv = vim.uv

local M = {}

local state = {
	client = nil,
	buffer = {},
	callbacks = {},
	next_id = 1,
}

---Check if connected to server
---@return boolean
function M.is_connected()
	return state.client ~= nil and not state.client:is_closing()
end

---Connect to Lisp server
---@param host string
---@param port integer
function M.connect(host, port)
	if M.is_connected() then
		return
	end

	state.client = uv.new_tcp()
	state.client:connect(host, port, function(err)
		if err then
			vim.schedule(function()
				vim.notify("Ooze: Failed to connect to " .. host .. ":" .. port, vim.log.levels.ERROR)
			end)
			state.client = nil
			return
		end

		vim.schedule(function()
			vim.notify("Ooze: Connected to " .. host .. ":" .. port, vim.log.levels.INFO)
		end)

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

---Disconnect from server
function M.disconnect()
	if state.client then
		if not state.client:is_closing() then
			state.client:close()
		end
		state.client = nil
	end
	state.buffer = {}
	state.callbacks = {}
	state.next_id = 1
end

---Send RPC message
---@param data table
---@param cb? function
function M.send(data, cb)
	if not M.is_connected() then
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
