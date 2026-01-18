local M = {}

local uv = vim.uv

---Connects to a TCP server and sets up read/close handlers.
---@param host string
---@param port integer
---@param handlers { on_connect: fun(), on_data: fun(data: string), on_close: fun(), on_error: fun(err: string) }
---@return table client: The TCP client object.
function M.connect(host, port, handlers)
	local client = uv.new_tcp()
	client:connect(host, port, function(err)
		if err then
			handlers.on_error(err)
			return
		end
		if handlers.on_connect then
			handlers.on_connect()
		end

		client:read_start(function(read_err, data)
			if read_err or not data then
				handlers.on_close()
				return
			end
			handlers.on_data(data)
		end)
	end)
	return client
end

---Sends a Lua table over the TCP socket with length-prefixing.
---@param client table: The TCP client object from connect().
---@param msg_table table: The Lua table to send.
function M.send(client, msg_table)
	if client and not client:is_closing() then
		local msg = vim.json.encode(msg_table)
		client:write(string.format("%06X%s", #msg, msg))
	end
end

---Closes the TCP client.
---@param client table: The TCP client object.
function M.close(client)
	if client and not client:is_closing() then
		client:close()
	end
end

return M
