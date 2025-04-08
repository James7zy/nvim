-- Set the mapleader key to space in Lua
vim.g.mapleader = ' '

-- plugins
require('plugins')

--colorscheme
require('colorscheme')

--lsp
require('lsp')

--load keymappings
require("keymaps")

-- load options
require("options")
