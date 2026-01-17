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
---@field err? string

---@class Ooze.EvalOpts
---@field silent? boolean If true, don't echo the input code in REPL.
