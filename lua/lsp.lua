-- =========================================
-- Mason setup
-- =========================================
require('mason').setup({
    ui = {
        icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗"
        }
    }
})

require('mason-lspconfig').setup({
    ensure_installed = { 'lua_ls', 'clangd', 'pylsp' },
    automatic_installation = true,
})

-- =========================================
-- Diagnostics global keymaps
-- =========================================
local opts = { noremap = true, silent = true }
vim.keymap.set('n', '<space>e', vim.diagnostic.open_float, opts)
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
vim.keymap.set('n', '<space>q', vim.diagnostic.setloclist, opts)

-- =========================================
-- on_attach for all LSP servers
-- =========================================
local on_attach = function(client, bufnr)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

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
    vim.keymap.set('n', '<space>f', function()
        vim.lsp.buf.format({ async = true })
    end, bufopts)
end

-- =========================================
-- Get clangd path (Mason fallback)
-- =========================================
local function get_clangd_path()
    local mason_path = vim.fn.stdpath("data") .. "/mason"
    local clangd_path = mason_path .. "/bin/clangd"
    if vim.fn.executable(clangd_path) == 1 then
        vim.notify("Found clangd at: " .. clangd_path, vim.log.levels.INFO)
        return clangd_path
    else
        vim.notify("clangd not found at: " .. clangd_path .. ", falling back to system clangd", vim.log.levels.WARN)
        return "clangd"
    end
end

local clangd_path = get_clangd_path()

-- =========================================
-- Capabilities (for nvim-cmp completion)
-- =========================================
local capabilities = require("cmp_nvim_lsp").default_capabilities()
capabilities.offsetEncoding = { "utf-16" }

-- =========================================
-- Register LSP servers using new API
-- =========================================
-- pylsp
vim.lsp.config['pylsp'] = {
    default_config = {
        cmd = { "pylsp" },
        filetypes = { "python" },
        root_dir = vim.fs.dirname(vim.fs.find({ '.git', 'pyproject.toml', 'setup.py' }, { upward = true })[1]),
        settings = {},
    },
}
vim.lsp.start(vim.lsp.config['pylsp'], { on_attach = on_attach })

-- clangd
vim.lsp.config['clangd'] = {
    default_config = {
        cmd = {
            clangd_path,
            "--background-index",
            "--clang-tidy",
            "--header-insertion=never",
            "--all-scopes-completion",
            "--enable-config",
            "--completion-style=detailed",
            "--function-arg-placeholders",
            "--rename-file-limit=0",
            "--background-index-priority=normal",
        },
        filetypes = { "c", "cpp", "objc", "objcpp" },
        root_dir = vim.fs.dirname(vim.fs.find({ '.git' }, { upward = true })[1]),
        capabilities = capabilities,
    },
}
vim.lsp.start(vim.lsp.config['clangd'], { on_attach = on_attach })

-- lua_ls
vim.lsp.config['lua_ls'] = {
    default_config = {
        cmd = { "lua-language-server" },
        filetypes = { "lua" },
        root_dir = vim.fs.dirname(vim.fs.find({ '.git', '.luarc.json', '.luacheckrc' }, { upward = true })[1]),
        settings = {
            Lua = {
                runtime = { version = 'LuaJIT' },
                diagnostics = { globals = { 'vim' } },
                workspace = { library = vim.api.nvim_get_runtime_file("", true) },
                telemetry = { enable = false },
            },
        },
    },
}
vim.lsp.start(vim.lsp.config['lua_ls'], { on_attach = on_attach })

