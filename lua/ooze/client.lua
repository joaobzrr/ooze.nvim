local M = {}

local rpc = require("ooze.rpc")
local config = require("ooze.config")

local uv = vim.uv

---@type Ooze.ClientState
local state = {
	client = nil,
	conn_state = "disconnected",
	buffer = "",
	callbacks = {},
	next_id = 1,
	pending = {},
}

local function drain_buffer()
	while #state.buffer >= 6 do
		local result, consumed, err = rpc.decode(state.buffer)

		if err then
			vim.schedule(function()
				vim.notify("Ooze: Decode error: " .. err, vim.log.levels.ERROR)
			end)
			state.buffer = ""
			return
		end

		if not result or consumed == 0 then
			return
		end

		state.buffer = state.buffer:sub(consumed + 1)

		local cb = state.callbacks[result.id]
		state.callbacks[result.id] = nil
		if cb then
			vim.schedule(function()
				cb(result)
			end)
		end
	end
end

local function teardown(err)
	if state.client then
		if not state.client:is_closing() then
			state.client:close()
		end
		state.client = nil
	end

	state.conn_state = "disconnected"
	state.buffer = ""

	local err_msg = err or "Disconnected"

	local callbacks = state.callbacks
	state.callbacks = {}
	for _, cb in pairs(callbacks) do
		vim.schedule(function()
			cb({ ok = false, err = err_msg or "Disconnected" })
		end)
	end

	local pending = state.pending
	state.pending = {}
	for _, item in ipairs(pending) do
		vim.schedule(function()
			item.cb({ ok = false, err = err_msg or "Disconnected" })
		end)
	end
end

function M.connect()
	if state.conn_state ~= "disconnected" then
		return
	end

	local client, err = uv.new_tcp()
	state.client = client

	if not client then
		vim.schedule(function()
			vim.notify("Ooze: Failed to create TCP client: " .. err, vim.log.levels.ERROR)
		end)
		return
	end

	state.conn_state = "connecting"

	local conf = config.get_config()
	client:connect(conf.server.host, conf.server.port, function(err)
		if err then
			vim.schedule(function()
				vim.notify("Ooze: Connection failed: " .. err, vim.log.levels.ERROR)
				teardown(err)
			end)
			return
		end

		state.conn_state = "connected"
		vim.schedule(function()
			vim.notify("Ooze: Connected to " .. conf.server.host .. ":" .. conf.server.port, vim.log.levels.INFO)

			local queue = state.pending
			state.pending = {}
			for _, item in ipairs(queue) do
				M.send(item.data, item.cb)
			end
		end)

		client:read_start(function(err, data)
			if err or not data then
				teardown(err)
				return
			end

			state.buffer = state.buffer .. data
			drain_buffer()
		end)
	end)
end

function M.disconnect()
	if state.client and not state.client:is_closing() then
		state.client:close()
		teardown()
	end
end

function M.send(data, cb)
	if state.conn_state ~= "connected" then
		table.insert(state.pending, { data = data, cb = cb })
		M.connect()
		return
	end

	local id = state.next_id
	state.next_id = id + 1
	state.callbacks[id] = cb

	local payload = vim.tbl_extend("force", data, { id = id })
	local msg = rpc.encode(payload)

	state.client:write(msg, function(err)
		if err then
			teardown("Write error: " .. err)
		end
	end)
end

function M.ping(cb)
	M.send({ op = "ping" }, cb)
end

function M.eval(code, cb)
	M.send({ op = "eval", code = code }, cb)
end

return M
