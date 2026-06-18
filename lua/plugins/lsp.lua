return {
  -- LSP manager + servers
  "williamboman/mason.nvim",
  "williamboman/mason-lspconfig.nvim",
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- ============ Mason ============
      require('mason').setup({
        ui = {
          icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗",
          },
        },
      })

      require('mason-lspconfig').setup({
        -- clangd 的预编译二进制不支持 aarch64（树莓派），改用系统包管理器安装的
        -- /usr/bin/clangd（apt install clangd），下面 vim.lsp.config 直接走 PATH。
        ensure_installed = { 'lua_ls', 'pylsp' },
        automatic_installation = false,
      })

      -- ============ Diagnostics global keymaps ============
      local opts = { noremap = true, silent = true }
      vim.keymap.set('n', '<space>e', vim.diagnostic.open_float, opts)
      vim.keymap.set('n', '[d', function() vim.diagnostic.jump({ count = -1, float = true }) end, opts)
      vim.keymap.set('n', ']d', function() vim.diagnostic.jump({ count = 1, float = true }) end, opts)
      vim.keymap.set('n', '<space>q', vim.diagnostic.setloclist, opts)

      -- ============ Shared on-attach via LspAttach ============
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('UserLspConfig', {}),
        callback = function(ev)
          vim.bo[ev.buf].omnifunc = 'v:lua.vim.lsp.omnifunc'

          local bufopts = { noremap = true, silent = true, buffer = ev.buf }
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
        end,
      })

      -- ============ Global capabilities (for nvim-cmp) ============
      local capabilities = require("cmp_nvim_lsp").default_capabilities()
      capabilities.offsetEncoding = { "utf-16" }
      vim.lsp.config('*', { capabilities = capabilities })

      -- ============ Server definitions ============
      vim.lsp.config('pylsp', {
        cmd = { "pylsp" },
        filetypes = { "python" },
        root_markers = { '.git', 'pyproject.toml', 'setup.py' },
        settings = {},
      })

      vim.lsp.config('clangd', {
        cmd = {
          "clangd",
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
        root_markers = { '.git' },
      })

      vim.lsp.config('lua_ls', {
        cmd = { "lua-language-server" },
        filetypes = { "lua" },
        root_markers = { '.git', '.luarc.json', '.luacheckrc' },
        settings = {
          Lua = {
            runtime = { version = 'LuaJIT' },
            diagnostics = { globals = { 'vim' } },
            workspace = { library = vim.api.nvim_get_runtime_file("", true) },
            telemetry = { enable = false },
          },
        },
      })

      vim.lsp.enable({ 'pylsp', 'clangd', 'lua_ls' })
    end,
  },
}
