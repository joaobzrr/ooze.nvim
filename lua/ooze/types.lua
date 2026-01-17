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
---@field echo? boolean If true, echo the input code in REPL (used for buffer evals).
