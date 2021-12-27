<div id="container">
    <img alt=NeoDo" src="assets/neodo_logo.png" />
</div>

## Description

Neodo can do these things:
* Detect projet root and automatically change directory
* Detect projet type(Javascript project, CMake project, PHP-Componser project, UserDefinedType, etc...)
* Define commands for project types
* Define commands for specific project types
* Run defined commands in:
    * background,
    * terminal
    * or as lua function.
* Call custom function when project file is opened(usefull for configuring buffer keybindings)
* Call custom functino when project is detected for the first time.
* Project specific configuration files of two types:
    * In the source tree (.neodo/config.lua) file in the root of the project
    * Out of source tree config file located in `_datapath_/neodo/hash_of_project_path/config.lua`
    
## Installation

Using `packer`:

```lua
use {
    'JanValiska/neodo',
    branch = 'devel'
}
```

## Configuration

The `setup()` function must be called to properly initialize plugin.
User can pass config paramters to this function to change default behavior of plugin or to add project type specific bindings.

Example:

```lua
local function bind_mongoose_keys()
    local opts = {noremap = true, silent = true}
    vim.api.nvim_buf_set_keymap(0, "n", "<leader>mb",
                                [[:lua require'neodo'.run('build')<CR>]], opts)
    vim.api.nvim_buf_set_keymap(0, "n", "<leader>mf",
                                [[:lua require'neodo'.run('flash')<CR>]], opts)
end

local function bind_cmake_keys()
    local opts = {noremap = true, silent = true}
    vim.api.nvim_buf_set_keymap(0, "n", "<leader>mb",
                                [[:lua require'neodo'.run('build_all')<CR>]], opts)
end

require'neodo'.setup({
    project_type = {
        mongoose = {user_buffer_on_attach = bind_mongoose_keys},
        cmake = {user_buffer_on_attach = bind_cmake_keys}
    }
})
```

### Definition of new project type

To add new project type add configuration to `setup()` function.
For example to add support for `Javascript` projects use this command:

```lua

local javascript = {
    name = "JS",
    commands = {
        update = {
            type = 'terminal',
            name = 'Update packages using NPM',
            cmd = 'npm update'
        }
    },
    patterns = {'packages.json'},
    buffer_on_attach = function()
        local opts = {noremap = true, silent = true}
        vim.api.nvim_buf_set_keymap(0, "n", "<leader>up",
                                    [[:lua require'neodo'.run('update')<CR>]], opts)
    end
}

require'neodo'.setup({
    project_type = {
        javascript = javascript,
    }
})
```

Commands above basically means that every folder which has `packages.json` file is considered as project root and also as `javascript` project. Every buffer with opened file from this project directory will have `<leader>up` keybinding defined.

The `update` command can be then executed using defined keybinding, or using `:Neodo update` or using `:Neodo` which will open telescope based command picker.

Command for can be called also from `lua` using `require('neodo).run('update')`.

### Using project specific configuration

TODO

## Currently supported project types

- Generic project(every project that is not specific)

Specific project types:
- Mongoose OS (for embeeded development)
- CMake (partial support)
- PHP using composer

## Feature/Road map

- Auto-reload of project specific config files
- Integration with already available language tools like: `rust-tools`, `neovim-cmake`, etc...
