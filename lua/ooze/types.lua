---@meta

---@class Ooze.EvalResult
---@field ok boolean
---@field value? string
---@field stdout? string
---@field err? string

---@class Ooze.RpcRequest
---@field data any
---@field cb fun(res: Ooze.RpcResponse)

---@class Ooze.RpcResponse
---@field id integer
---@field ok boolean
---@field results? Ooze.EvalResult[]
---@field ["package"]? string
---@field err? string

---@alias Ooze.RpcConnState "disconnected" | "connecting" | "connected"

---@class Ooze.RpcState
---@field client uv.uv_tcp_t?
---@field conn_state Ooze.RpcConnState
---@field buffer string[]
---@field next_id integer
---@field pending Ooze.RpcRequest[]

---@class Ooze.EvalOpts
---@field echo? boolean

---@class Ooze.ConfigServer
---@field host string
---@field port integer

---@class Ooze.Config
---@field server Ooze.ConfigServer

---@class Ooze.ReplState
---@field buf integer? The REPL buffer handle
---@field win integer? The REPL window handle
---@field current_package string The current Lisp package
---@field prompt_format string Format string for the prompt
---@field history string[] List of submitted commands
---@field history_index integer Current position in history navigation
---@field on_submit fun(code: string)

return {}
