---@module 'ooze.config'

---@class OozeConfigServer
---@field host string The host address of the Lisp server.
---@field port integer The port number of the Lisp server.

---@class OozeConfig
---@field server OozeConfigServer Server connection settings.

---@type OozeConfig
local M = {
	server = {
		host = "127.0.0.1",
		port = 4005,
	},

	-- TODO: Add more configuration options here later,
	-- such as keymaps, UI settings, etc.
}

return M
