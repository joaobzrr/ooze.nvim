---@module 'ooze.rpc'

local struct = require("ooze.struct")
local uv = vim.uv

local M = {}

---@alias OozeRpcPrimitive string|number|boolean|nil
---@alias OozeRpcValue OozeRpcPrimitive|table<string, OozeRpcValue>

---@class OozeRpcRequest
---@field id? integer
---@field op string
---@field code? string
---@field symbol? string
---@field package? string
---@field [string] OozeRpcValue

---@class OozeRpcResponse
---@field id integer
---@field err? string
---@field [string] OozeRpcValue

---@alias OozeRpcCallback fun(response: OozeRpcResponse): nil

---@class OozeRpcState
---@field client uv.uv_tcp_t?            -- Active TCP client (nil when disconnected)
---@field buffer string                  -- Incoming message buffer
---@field callbacks table<integer, OozeRpcCallback>
---@field next_id integer

---@type OozeRpcState
local state = {
	client = nil,
	buffer = "",
	callbacks = {},
	next_id = 1,
}

---Send a request if connected.
---@param data OozeRpcRequest
---@param cb OozeRpcCallback?
local function _request(data, cb)
	if not state.client or state.client:is_closing() then
		if cb then
			vim.schedule(function()
				cb({ err = "Not connected to Lisp server.", id = -1 })
			end)
		end
		return
	end

	local id = state.next_id
	state.next_id = id + 1

	if cb then
		state.callbacks[id] = cb
	end

	data.id = id

	local message = struct.serialize(data)
	local wrapped = string.format("%06X%s", #message, message)

	state.client:write(wrapped)
end

---Connect to the Lisp RPC server.
---@param host string
---@param port integer
---@param on_connect fun()? Optional callback invoked after successful connection
function M.connect(host, port, on_connect)
	if state.client and not state.client:is_closing() then
		return
	end

	state.client = uv.new_tcp()

	state.client:connect(host, port, function(err)
		if err then
			if state.client and not state.client:is_closing() then
				state.client:close()
			end

			state.client = nil

			vim.schedule(function()
				vim.notify("Ooze RPC: Connection failed: " .. tostring(err), vim.log.levels.ERROR)
			end)

			return
		end

		if on_connect then
			vim.schedule(on_connect)
		end

		state.client:read_start(function(read_err, data)
			if read_err then
				vim.schedule(function()
					vim.notify("Ooze RPC Read Error: " .. tostring(read_err), vim.log.levels.ERROR)
				end)
				return
			end

			if not data then
				return
			end

			state.buffer = state.buffer .. data

			while #state.buffer >= 6 do
				local header = state.buffer:sub(1, 6)
				local len = tonumber(header, 16)

				if not len then
					vim.notify("Ooze RPC: Invalid frame length header: " .. vim.inspect(header), vim.log.levels.ERROR)

					state.buffer = ""
					return
				end

				if #state.buffer < 6 + len then
					-- incomplete frame, wait for more data
					return
				end

				local body = state.buffer:sub(7, 6 + len)
				state.buffer = state.buffer:sub(6 + len + 1)

				body = body:match("^%s*(.-)%s*$") or ""

				local ok, parsed = pcall(struct.parse, body)
				if not ok then
					vim.notify("Ooze RPC: Failed to parse JSON body", vim.log.levels.ERROR)
					break
				end

				local cb = state.callbacks[parsed.id]
				if cb then
					state.callbacks[parsed.id] = nil
					vim.schedule(function()
						cb(parsed)
					end)
				else
					vim.notify("Ooze RPC: Response for unknown request id " .. parsed.id, vim.log.levels.WARN)
				end
			end
		end)
	end)
end

---Send an evaluation request.
---@param form string
---@param cb OozeRpcCallback?
function M.send(form, cb)
	_request({
		op = "eval",
		code = form,
	}, cb)
end

---Send a symbol description request.
---@param symbol string
---@param cb OozeRpcCallback?
function M.describe(symbol, cb)
	_request({
		op = "describe",
		symbol = symbol,
	}, cb)
end

---Disconnect from the Lisp RPC server.
function M.disconnect()
	if not state.client or state.client:is_closing() then
		return
	end

	state.client:close()
	state.client = nil

	for id, cb in pairs(state.callbacks) do
		vim.schedule(function()
			cb({ err = "Disconnected.", id = id })
		end)
	end

	state.buffer = ""
	state.callbacks = {}
	state.next_id = 1

	vim.notify("Ooze RPC: Disconnected.", vim.log.levels.INFO)
end

return M
