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
        -- clangd 不交给 mason 管理：其预编译二进制不支持 aarch64（树莓派），
        -- 改用系统 PATH 上的 clangd（见下方 resolve_clangd 自动探测）。
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

      -- ============ clangd 二进制探测（可移植）============
      -- 不写死版本号：优先选 PATH 上版本最高的 clangd（clangd-22 > clangd-18 >
      -- … > clangd），找不到带版本后缀的就回退到裸 clangd。这样同一份配置在
      -- 不同机器（树莓派 / 其他发行版 / 自带较老 clangd）上都能自适应。
      local function resolve_clangd()
        local candidates = { "clangd" }
        -- 探测 clangd-NN（NN 从高到低），命中即用。
        for ver = 30, 15, -1 do
          table.insert(candidates, 1, "clangd-" .. ver)
        end
        for _, bin in ipairs(candidates) do
          if vim.fn.executable(bin) == 1 then
            return bin
          end
        end
        return nil
      end

      -- 探测 clangd 主版本号，用于决定是否启用版本相关参数。
      local function clangd_major(bin)
        local out = vim.fn.system({ bin, "--version" })
        local major = out:match("clangd version (%d+)")
        return tonumber(major)
      end

      local clangd_bin = resolve_clangd()
      if clangd_bin then
        local clangd_cmd = {
          clangd_bin,
          "--background-index",
          "--clang-tidy",
          "--header-insertion=never",
          "--all-scopes-completion",
          "--enable-config",
          "--completion-style=detailed",
          "--function-arg-placeholders",
        }
        -- 这两个参数在 clangd 15+ 才支持，旧版本传入会导致进程以 exit 1 退出。
        local major = clangd_major(clangd_bin)
        if major and major >= 15 then
          table.insert(clangd_cmd, "--rename-file-limit=0")
          table.insert(clangd_cmd, "--background-index-priority=normal")
        end

        vim.lsp.config('clangd', {
          cmd = clangd_cmd,
          filetypes = { "c", "cpp", "objc", "objcpp" },
          root_markers = { '.git' },
        })
      else
        vim.notify("clangd 未安装，C/C++ LSP 未启用", vim.log.levels.WARN)
      end

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

      local servers = { 'pylsp', 'lua_ls' }
      if clangd_bin then
        table.insert(servers, 'clangd')
      end
      vim.lsp.enable(servers)
    end,
  },
}
