require('mason').setup({
    ui = {
        icons = {
            package_installed = "install",
            package_pending = "pending",
            package_uninstalled = "uninstall"
        }
    }
})

require('mason-lspconfig').setup({
    -- A list of servers to automatically install if they're not already installed
    ensure_installed = { 'lua_ls', 'rust_analyzer','clangd' },
})

-- Set different settings for different languages' LSP
-- LSP list: https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md
-- How to use setup({}): https://github.com/neovim/nvim-lspconfig/wiki/Understanding-setup-%7B%7D
--     - the settings table is sent to the LSP
--     - on_attach: a lua callback function to run after LSP atteches to a given buffer
local lspconfig = require('lspconfig')

-- Customized on_attach function
-- See `:help vim.diagnostic.*` for documentation on any of the below functions
local opts = { noremap = true, silent = true }
vim.keymap.set('n', '<space>e', vim.diagnostic.open_float, opts)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
vim.keymap.set('n', '<space>q', vim.diagnostic.setloclist, opts)

-- Use an on_attach function to only map the following keys
-- after the language server attaches to the current buffer
local on_attach = function(client, bufnr)
    -- Enable completion triggered by <c-x><c-o>
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

    -- See `:help vim.lsp.*` for documentation on any of the below functions
    local bufopts = { noremap = true, silent = true, buffer = bufnr }
    vim.keymap.set('n', 'gD', vim.lsp.buf.declaration, bufopts)
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
    vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
    vim.keymap.set('n', 'gi', vim.lsp.buf.implementation, bufopts)
    vim.keymap.set('n', '<C-k>', vim.lsp.buf.signature_help, bufopts)
    vim.keymap.set('n', '<space>wa', vim.lsp.buf.add_workspace_folder, bufopts)
    vim.keymap.set('n', '<space>wr', vim.lsp.buf.remove_workspace_folder, bufopts)
    vim.keymap.set('n', '<space>wl', function()
        print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
    end, bufopts)
    vim.keymap.set('n', '<space>D', vim.lsp.buf.type_definition, bufopts)
    vim.keymap.set('n', '<space>rn', vim.lsp.buf.rename, bufopts)
    vim.keymap.set('n', '<space>ca', vim.lsp.buf.code_action, bufopts)
    vim.keymap.set('n', 'gr', vim.lsp.buf.references, bufopts)
    vim.keymap.set("n", "<space>f", function()
        vim.lsp.buf.format({ async = true })
    end, bufopts)
end

-- Configure each language
-- How to add LSP for a specific language?
-- 1. use `:Mason` to install corresponding LSP
-- 2. add configuration below
lspconfig.pylsp.setup({
	on_attach = on_attach,
})

-- clangd 配置
local mason_registry = require("mason-registry")

local function get_clangd_path()
    local pkg = mason_registry.get_package("clangd")
    local install_dir = pkg:get_install_path()

    -- 递归查找 clangd 可执行文件
    local handle = vim.loop.fs_scandir(install_dir)
    while handle do
        local name, typ = vim.loop.fs_scandir_next(handle)
        if not name then break end
        if typ == "directory" and name:match("^clangd_") then
            local clangd_exec = install_dir .. "/" .. name .. "/bin/clangd"
            if vim.fn.filereadable(clangd_exec) == 1 then
                return clangd_exec
            end
        end
    end

    -- fallback 路径（旧版本的 mason 路径）
    local fallback = install_dir .. "/bin/clangd"
    if vim.fn.filereadable(fallback) == 1 then
        return fallback
    end

    vim.notify("[clangd] could not find executable", vim.log.levels.ERROR)
    return "clangd" -- fallback to system clangd
end

local clangd_path = get_clangd_path()

lspconfig.clangd.setup({
    cmd = {
        clangd_path,
        "--background-index",
        "--clang-tidy",
        "--header-insertion=never",
        "--all-scopes-completion",
        "--enable-config",
        "--completion-style=detailed"
    },
    on_attach = on_attach,
})

