local M = {}

-- Store config globally to persist across reloads, but keep it internal to the plugin files.
-- This ensures that user settings are not lost when the plugin is reloaded.
_G._ooze = _G._ooze or {}
_G._ooze.config = _G._ooze.config or {}

---@class Ooze.Config
local default_config = {
	server = {
		host = "127.0.0.1",
		port = 4005,
	},
}
---Setup function to merge user config.
---This is called from init.lua when the plugin is set up.
---@param opts? Ooze.Config
function M.setup(opts)
	_G._ooze.config = vim.tbl_deep_extend("force", {}, default_config, opts or {})
end

---Get current config.
---If setup has not been run, it initializes with defaults.
---@return Ooze.Config
function M.get_config()
	if not _G._ooze.config.server then
		M.setup()
	end
	return _G._ooze.config
end

return M
