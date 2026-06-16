-- Set the mapleader key to space (must precede lazy + plugin loading)
vim.g.mapleader = ' '

-- ============ lazy.nvim bootstrap ============
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ============ Core settings ============
require("options")
require("keymaps")

-- ============ Plugins (auto-import lua/plugins/) ============
require("lazy").setup("plugins")
