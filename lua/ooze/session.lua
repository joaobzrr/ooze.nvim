local M = {}

local rpc = require("ooze.rpc")
local config = require("ooze.config")

---@class Ooze.SessionState
local state = {
	client = nil,
	conn_state = "disconnected", -- disconnected, connecting, connected
	buffer = "",
	callbacks = {},
	next_id = 1,
	pending = {},
}

local function process_buffer()
	while #state.buffer >= 6 do
		local len = tonumber(state.buffer:sub(1, 6), 16)
		if not len or #state.buffer < (6 + len) then
			break
		end

		local body = state.buffer:sub(7, 6 + len)
		state.buffer = state.buffer:sub(6 + len + 1)

		local ok, parsed = pcall(vim.json.decode, body)
		if ok and parsed.id then
			local cb = state.callbacks[parsed.id]
			state.callbacks[parsed.id] = nil
			if cb then
				vim.schedule(function()
					cb(parsed)
				end)
			end
		end
	end
end

local function flush_pending()
	for _, item in ipairs(state.pending) do
		M.send(item.data, item.cb)
	end
	state.pending = {}
end

local function cleanup_session(err_msg)
	state.conn_state = "disconnected"
	state.buffer = ""
	state.next_id = 1

	for id, cb in pairs(state.callbacks) do
		vim.schedule(function()
			cb({ ok = false, err = err_msg or "Disconnected" })
		end)
		state.callbacks[id] = nil
	end

	for _, item in ipairs(state.pending) do
		vim.schedule(function()
			item.cb({ ok = false, err = err_msg or "Disconnected" })
		end)
	end

	state.pending = {}
end

function M.connect()
	if state.conn_state ~= "disconnected" then
		return
	end
	state.conn_state = "connecting"

	local conf = config.get_config()
	state.client = rpc.connect(conf.server.host, conf.server.port, {
		on_connect = function()
			state.conn_state = "connected"

			vim.schedule(function()
				vim.notify("Ooze: Connected to " .. conf.server.host .. ":" .. conf.server.port, vim.log.levels.INFO)
				vim.schedule(flush_pending)
			end)
		end,
		on_data = function(data)
			state.buffer = state.buffer .. data
			process_buffer()
		end,
		on_close = function()
			cleanup_session()
		end,
		on_error = function(err)
			cleanup_session(err)
			vim.schedule(function()
				vim.notify("Ooze: Connection failed: " .. err, vim.log.levels.ERROR)
			end)
		end,
	})
end

function M.disconnect()
	if state.client then
		rpc.close(state.client)
		state.client = nil
		cleanup_session()
	end
end

function M.send(data, cb)
	if state.conn_state ~= "connected" then
		table.insert(state.pending, { data = data, cb = cb })
		if state.conn_state == "disconnected" then
			M.connect()
		end
		return
	end

	local id = state.next_id
	state.next_id = id + 1
	state.callbacks[id] = cb
	local payload = vim.tbl_extend("force", data, { id = id })
	rpc.send(state.client, payload)
end

function M.ping(cb)
	M.send({ op = "ping" }, cb)
end

function M.eval(code, cb)
	print(string.format("session.eval called. Type of 'cb' is: %s", type(cb)))

	M.send({ op = "eval", code = code }, cb)
end

function M.is_connected()
	return state.conn_state == "connected"
end

return M
