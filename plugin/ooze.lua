-- This file handles plugin initialization (not loaded by lazy.nvim)
-- It sets up commands and autocommands that lazy-load the actual plugin

-- Early return if already loaded
if vim.g.loaded_ooze then
    return
end
vim.g.loaded_ooze = true

-- Create user commands that lazy-load the plugin
vim.api.nvim_create_user_command("OozeEvalEnclosing", function()
    require("ooze").eval_enclosing()
end, { desc = "Ooze: Evaluate enclosing form" })

vim.api.nvim_create_user_command("OozeEvalOutermost", function()
    require("ooze").eval_outermost()
end, { desc = "Ooze: Evaluate outermost form" })

vim.api.nvim_create_user_command("OozeEvalBuffer", function()
    require("ooze").eval_buffer()
end, { desc = "Ooze: Evaluate buffer" })

vim.api.nvim_create_user_command("OozeEvalRegion", function()
    require("ooze").eval_region()
end, { range = true, desc = "Ooze: Evaluate visual selection" })

vim.api.nvim_create_user_command("OozeReplToggle", function()
    require("ooze").toggle_repl()
end, { desc = "Ooze: Toggle REPL" })

vim.api.nvim_create_user_command("OozeReload", function()
    require("ooze").reload()
end, { desc = "Ooze: Reload plugin" })

vim.api.nvim_create_user_command("OozeReplClear", function()
    require("ooze.repl").clear()
end, { desc = "Ooze: Clear REPL" })

vim.api.nvim_create_user_command("OozeConnect", function()
    require("ooze.client").connect()
end, { desc = "Ooze: Connect to server" })

vim.api.nvim_create_user_command("OozeDisconnect", function()
    require("ooze.client").disconnect()
end, { desc = "Ooze: Disconnect from server" })

-- Set up FileType autocommand for lazy loading
vim.api.nvim_create_autocmd("FileType", {
    pattern = "lisp",
    callback = function(args)
        local opts = { buffer = args.buf, silent = true }

        -- These keymaps will lazy-load the plugin on first use
        vim.keymap.set("n", "<leader>ee", function()
            require("ooze").eval_enclosing()
        end, vim.tbl_extend("force", opts, { desc = "Ooze: Eval enclosing" }))

        vim.keymap.set("n", "<leader>er", function()
            require("ooze").eval_outermost()
        end, vim.tbl_extend("force", opts, { desc = "Ooze: Eval outermost" }))

        vim.keymap.set("n", "<leader>eb", function()
            require("ooze").eval_buffer()
        end, vim.tbl_extend("force", opts, { desc = "Ooze: Eval buffer" }))

        vim.keymap.set(
            "v",
            "<leader>ev",
            ":<C-u>OozeEvalRegion<CR>",
            vim.tbl_extend("force", opts, { desc = "Ooze: Eval selection" })
        )

        vim.keymap.set("n", "<leader>rt", function()
            require("ooze").toggle_repl()
        end, vim.tbl_extend("force", opts, { desc = "Ooze: Toggle REPL" }))

        vim.keymap.set("n", "<leader>rc", function()
            require("ooze.repl").clear()
        end, vim.tbl_extend("force", opts, { desc = "Ooze: Clear REPL" }))
    end,
})
