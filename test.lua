-- Test script for Ooze plugin
-- Source this file in Neovim to test the plugin: :source %

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("✓ " .. name)
    else
        print("✗ " .. name .. ": " .. tostring(err))
    end
end

print("\n=== Ooze Plugin Tests ===\n")

test("Plugin can be loaded", function()
    local ooze = require("ooze")
    assert(ooze ~= nil, "Failed to load ooze module")
end)

test("Config is accessible", function()
    local ooze = require("ooze")
    local config = ooze.get_config()
    assert(config ~= nil, "Config is nil")
    assert(config.server ~= nil, "Server config is nil")
    assert(config.server.host ~= nil, "Host is nil")
    assert(config.server.port ~= nil, "Port is nil")
end)

test("RPC module loads", function()
    local rpc = require("ooze.rpc")
    assert(rpc ~= nil, "Failed to load rpc module")
    assert(type(rpc.connect) == "function", "connect is not a function")
    assert(type(rpc.disconnect) == "function", "disconnect is not a function")
    assert(type(rpc.is_connected) == "function", "is_connected is not a function")
end)

test("REPL module loads", function()
    local repl = require("ooze.repl")
    assert(repl ~= nil, "Failed to load repl module")
    assert(type(repl.toggle) == "function", "toggle is not a function")
    assert(type(repl.is_open) == "function", "is_open is not a function")
end)

test("Tree-sitter module loads", function()
    local ts = require("ooze.ts")
    assert(ts ~= nil, "Failed to load ts module")
    assert(type(ts.get_enclosing_sexp) == "function", "get_enclosing_sexp is not a function")
    assert(type(ts.get_all_sexps) == "function", "get_all_sexps is not a function")
end)

test("UI module loads", function()
    local ui = require("ooze.ui")
    assert(ui ~= nil, "Failed to load ui module")
    assert(type(ui.format_eval_result) == "function", "format_eval_result is not a function")
end)

test("Commands are registered", function()
    local commands = vim.api.nvim_get_commands({})
    assert(commands.OozeEvalEnclosing ~= nil, "OozeEvalEnclosing not registered")
    assert(commands.OozeReplToggle ~= nil, "OozeReplToggle not registered")
    assert(commands.OozeReload ~= nil, "OozeReload not registered")
end)

test("Hot reload functionality", function()
    local ooze = require("ooze")
    assert(type(ooze.reload) == "function", "reload is not a function")

    -- Store initial config
    local config_before = ooze.get_config()

    -- Simulate reload
    for name, _ in pairs(package.loaded) do
        if name:match("^ooze") then
            package.loaded[name] = nil
        end
    end

    -- Re-require
    local ooze2 = require("ooze")
    assert(ooze2 ~= nil, "Failed to reload ooze module")

    -- Config should persist
    local config_after = ooze2.get_config()
    assert(vim.deep_equal(config_before, config_after), "Config not preserved across reload")
end)

test("Global config persists", function()
    local before = _G._ooze_config
    assert(before ~= nil, "Global config not set")

    -- Clear module cache
    for name, _ in pairs(package.loaded) do
        if name:match("^ooze") then
            package.loaded[name] = nil
        end
    end

    -- Re-require
    require("ooze")
    local after = _G._ooze_config

    assert(vim.deep_equal(before, after), "Global config changed after reload")
end)

print("\n=== All Tests Complete ===\n")

-- Print summary
print("Run :OozeReload to test hot reload functionality")
print("Run :OozeReplToggle to test REPL")
print("Open a .lisp file to test lazy loading")
