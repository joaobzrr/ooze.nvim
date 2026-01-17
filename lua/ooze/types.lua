---@meta

---@class Ooze.EvalResult
---@field ok boolean
---@field value? string
---@field stdout? string
---@field err? string

---@class Ooze.RpcResponse
---@field id integer
---@field ok boolean
---@field results? Ooze.EvalResult[]
---@field ["package"]? string
---@field err? string

---@class Ooze.EvalOpts
---@field echo? boolean

---@class Ooze.ConfigServer
---@field host string
---@field port integer

---@class Ooze.Config
---@field server Ooze.ConfigServer

---@class Ooze.ReplState
---@field buf integer|nil
---@field win integer|nil
---@field current_package string
---@field prompt_format string
---@field history string[]
---@field history_index integer

return {}
