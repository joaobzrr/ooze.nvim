# Ooze - Modern Neovim Common Lisp REPL Plugin

A fully reloadable, lazy-loaded Neovim plugin for interactive Common Lisp development.

## Features

- 🔄 **Full Hot-Reload** - Reload the entire plugin without restarting Neovim
- ⚡ **Lazy Loading** - Only loads when you need it (opening Lisp files or using commands)
- 🎯 **Smart Evaluation** - Evaluate forms, selections, or entire buffers
- 💬 **Interactive REPL** - Built-in REPL with history and package tracking
- 🌳 **Tree-sitter Integration** - Smart form detection using Tree-sitter

## Installation

### Prerequisites

1. Neovim 0.10+ with Tree-sitter support
2. Common Lisp implementation (SBCL, CCL, etc.)
3. The Ooze server running (see Server Setup below)

### Using lazy.nvim

```lua
-- In your lazy.nvim plugin spec (e.g., lua/plugins/ooze.lua)
local plugin_dir = os.getenv("OOZE_PLUGIN_DIR")
if not plugin_dir then
	error("OOZE_PLUGIN_DIR environment variable must be set")
end

return {
	dir = vim.fn.expand(plugin_dir),
	name = "ooze",
	lazy = true,
	ft = { "lisp", "commonlisp" },
	cmd = {
		"OozeEvalEnclosing",
		"OozeEvalOutermost",
		"OozeEvalBuffer",
		"OozeEvalRegion",
		"OozeReplToggle",
		"OozeReplClear",
		"OozeConnect",
		"OozeDisconnect",
		"OozeReload",
	},
	opts = {
		server = {
			host = "127.0.0.1",
			port = 4005,
		},
	},
}
```

### Environment Variable

Set the plugin directory in your shell config:

```bash
# In .bashrc, .zshrc, etc.
export OOZE_PLUGIN_DIR="$HOME/path/to/ooze"
```

## Server Setup

1. Load the Ooze server in your Lisp environment:

```lisp
(load "path/to/ooze-server.lisp")
(ooze-server:start-server :host "127.0.0.1" :port 4005)
```

2. Or start it from the command line:

```bash
sbcl --load ooze-server.lisp --eval "(ooze-server:main)"
```

## Usage

### Automatic Loading

The plugin automatically loads when you:
- Open a `.lisp` file
- Run any Ooze command

### Commands

| Command | Description |
|---------|-------------|
| `:OozeEvalEnclosing` | Evaluate the innermost form around cursor |
| `:OozeEvalOutermost` | Evaluate the top-level form around cursor |
| `:OozeEvalBuffer` | Evaluate entire buffer |
| `:OozeEvalRegion` | Evaluate visual selection |
| `:OozeReplToggle` | Open/close the REPL window |
| `:OozeReplClear` | Clear REPL buffer |
| `:OozeConnect` | Manually connect to server |
| `:OozeDisconnect` | Disconnect from server |
| `:OozeReload` | **Hot-reload the entire plugin** |

### Default Keymaps (in Lisp files)

| Key | Mode | Action |
|-----|------|--------|
| `<leader>ee` | Normal | Eval enclosing form |
| `<leader>er` | Normal | Eval outermost form |
| `<leader>eb` | Normal | Eval buffer |
| `<leader>ev` | Visual | Eval selection |
| `<leader>rt` | Normal | Toggle REPL |
| `<leader>rc` | Normal | Clear REPL |

### Custom Keymaps

You can customize keymaps in your plugin configuration:

```lua
return {
	dir = vim.fn.expand(os.getenv("OOZE_PLUGIN_DIR")),
	-- ... other config ...
	config = function(_, opts)
		require("ooze").setup(opts)
		
		-- Custom keymaps
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "lisp",
			callback = function(args)
				vim.keymap.set("n", "<localleader>e", function()
					require("ooze").eval_enclosing()
				end, { buffer = args.buf })
			end,
		})
	end,
}
```

## Hot Reloading

### Why Hot Reload?

During development, you often need to test changes without restarting Neovim. The `:OozeReload` command:

1. Closes the REPL if open
2. Disconnects from the server
3. Clears all cached Lua modules
4. Reloads the plugin with fresh code
5. Reconnects to the server

### Usage

```vim
:OozeReload
```

Or create a keymap:

```lua
vim.keymap.set("n", "<leader>or", "<cmd>OozeReload<CR>", { desc = "Reload Ooze plugin" })
```

### Development Workflow

1. Edit plugin code
2. Run `:OozeReload`
3. Test changes immediately
4. Repeat

## Architecture

### Lazy Loading Strategy

The plugin uses a multi-stage loading approach:

1. **plugin/ooze.lua** - Minimal initialization
   - Sets up commands and autocommands
   - No actual functionality loaded
   
2. **First Use** - Triggered by FileType or command
   - Loads `lua/ooze/init.lua`
   - Connects to server on-demand
   
3. **Module Loading** - As needed
   - Individual modules loaded when first accessed
   - Tree-sitter utils only loaded during evaluation

### State Management

- **Global Config** - Stored in `_G._ooze_config` to persist across reloads
- **RPC State** - Properly cleaned up during reload
- **REPL State** - Closed and recreated during reload

### Module Structure

```
lua/ooze/
├── init.lua      # Main plugin interface
├── rpc.lua       # RPC communication
├── repl.lua      # REPL buffer management
├── ts.lua        # Tree-sitter utilities
├── ui.lua        # UI formatting
└── types.lua     # Type annotations
```

## Configuration

### Full Configuration Example

```lua
return {
	dir = vim.fn.expand(os.getenv("OOZE_PLUGIN_DIR")),
	lazy = true,
	ft = { "lisp", "commonlisp" },
	cmd = { "OozeEvalEnclosing", "OozeReplToggle", "OozeReload" },
	opts = {
		server = {
			host = "127.0.0.1",
			port = 4005,
		},
	},
	config = function(_, opts)
		require("ooze").setup(opts)
		
		-- Additional setup
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "lisp",
			callback = function()
				-- Auto-connect on first Lisp file
				vim.defer_fn(function()
					require("ooze.rpc").connect(opts.server.host, opts.server.port)
				end, 100)
			end,
			once = true,
		})
	end,
}
```

## Troubleshooting

### Plugin Not Loading

1. Check that `OOZE_PLUGIN_DIR` is set correctly
2. Verify the plugin is in lazy.nvim's plugin list: `:Lazy`
3. Check for errors: `:messages`

### Server Connection Issues

1. Verify server is running: `netstat -an | grep 4005`
2. Try manual connection: `:OozeConnect`
3. Check server logs for errors

### Hot Reload Not Working

1. Ensure you saved your changes
2. Try `:OozeReload` twice if first attempt fails
3. Check `:messages` for error details

### REPL Issues

1. Clear and reopen: `:OozeReplClear` then `:OozeReplToggle`
2. Disconnect and reconnect: `:OozeDisconnect` then `:OozeConnect`
3. Full reload: `:OozeReload`

## Advanced Usage

### Programmatic API

```lua
local ooze = require("ooze")

-- Evaluate code
ooze.eval("(+ 1 2 3)", { echo = true })

-- Evaluate multiple forms
ooze.eval({ "(defun foo ())", "(foo)" }, { echo = false })

-- Get current config
local config = ooze.get_config()

-- Manual sync
ooze.sync_state()
```

### Integration with Other Plugins

```lua
-- Example: Integrate with telescope.nvim for form selection
local function eval_with_telescope()
	local ts = require("ooze.ts")
	local forms = ts.get_all_sexps()
	
	require("telescope.pickers").new({}, {
		prompt_title = "Eval Form",
		finder = require("telescope.finders").new_table({
			results = forms,
		}),
		attach_mappings = function(_, map)
			map("i", "<CR>", function(prompt_bufnr)
				local selection = require("telescope.actions.state").get_selected_entry()
				require("telescope.actions").close(prompt_bufnr)
				require("ooze").eval(selection.value, { echo = true })
			end)
			return true
		end,
	}):find()
end
```

## Contributing

When contributing:

1. Test your changes with `:OozeReload`
2. Ensure lazy loading still works
3. Update type annotations in `types.lua`
4. Follow existing code style

## License

[Your License Here]

## Credits

Built with modern Neovim plugin development practices.
