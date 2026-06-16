# Neovim 配置重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把单文件插件清单重构为「每插件一文件」的 lazy.nvim import 结构，配置内联，LSP 现代化到 0.11 写法，并修复 trouble 缺失文件 bug、清除 `get_clangd_path` 死代码——全程不改变现有行为（trouble 修复除外）。

**Architecture:** `init.lua` 负责引导（mapleader → lazy bootstrap → require options/keymaps → `lazy.setup('plugins')`）。`lua/plugins/` 下每个 `.lua` `return` 一个或一组插件 spec，配置内联进 `config`/`opts`/`init`。`lua/config/`、`lua/plugins.lua`、`lua/colorscheme.lua`、`lua/lsp.lua` 在迁移完成后删除。

**Tech Stack:** Neovim v0.11.5、lazy.nvim（`import` 机制）、Lua、mason + nvim-lspconfig + nvim-cmp。

**Spec:** `docs/superpowers/specs/2026-06-16-nvim-config-refactor-design.md`

---

## 验证约定（本项目无测试套件）

本项目没有单元测试。每个任务的"测试"是**用 headless Neovim 加载模块、确认无错误**。两个标准命令：

- **单模块加载检查**（验证某个 `plugins/*.lua` 能被 require 且返回 table）：
  ```bash
  nvim --headless -c "lua local ok,spec=pcall(require,'plugins.NAME'); assert(ok, spec); assert(type(spec)=='table', 'spec must be a table'); print('OK plugins.NAME')" -c "qa" 2>&1
  ```
  期望输出包含 `OK plugins.NAME`，无 `E5108`/`Error`/stack traceback。

- **整体启动检查**（验证 lazy 能解析整个 `plugins/` 目录、配置全部加载）：
  ```bash
  nvim --headless -c "lua print('loaded ' .. vim.tbl_count(require('lazy').plugins()) .. ' plugins')" -c "qa" 2>&1
  ```
  期望输出 `loaded N plugins`，无报错。

> 注意：纯 spec 文件（`return { ... }`，`config` 是闭包）在被 require 时**不会**执行 `config` 函数，所以单模块加载检查只验证 spec 语法和 table 结构；真正的 `config` 执行由整体启动检查覆盖。

> 迁移策略：每个 config 迁移任务采用 `git mv` 保留历史 + 包裹成 spec，而不是手敲重抄。具体见各任务。

---

## File Structure

| 文件 | 职责 | 来源 |
|------|------|------|
| `init.lua` | 引导：mapleader、lazy bootstrap、require options/keymaps、`lazy.setup('plugins')` | 改写 |
| `lua/options.lua` | vim 选项 | 不变 |
| `lua/keymaps.lua` | 全局快捷键（含 Copilot） | 不变 |
| `lua/plugins/colorscheme.lua` | kanagawa spec + setup | 原 `colorscheme.lua` |
| `lua/plugins/cmp.lua` | nvim-cmp + lspkind + LuaSnip + cmp-* | 原 spec + `config/nvim-cmp.lua` |
| `lua/plugins/lsp.lua` | mason/mason-lspconfig/nvim-lspconfig（0.11 写法） | 原 `lsp.lua` 现代化 |
| `lua/plugins/nvim-tree.lua` | nvim-tree spec + config | 原 spec + `config/nvim-tree.lua` |
| `lua/plugins/telescope.lua` | telescope spec + config | 原 spec + `config/telescope.lua` |
| `lua/plugins/treesitter.lua` | treesitter + textobjects（合一） | 原 2 个 spec + 2 个 config |
| `lua/plugins/aerial.lua` | aerial spec + config（400 行原样） | 原 spec + `config/aerial.lua` |
| `lua/plugins/tagbar.lua` | tagbar spec + config | 原 spec + `config/tagbar.lua` |
| `lua/plugins/easymotion.lua` | easymotion spec + config | 原 spec + `config/easymotion.lua` |
| `lua/plugins/highlighter.lua` | vim-highlighter spec + config | 原 spec + `config/vim-highlighter.lua` |
| `lua/plugins/bufferline.lua` | bufferline spec + config | 原 spec + `config/bufferline.lua` |
| `lua/plugins/trouble.lua` | trouble spec（**修复 bug**） | 原 spec 修正 |
| `lua/plugins/claude.lua` | claude-code spec + config | 原 spec + `config/claude.lua` |
| `lua/plugins/markdown.lua` | vim-markdown + markdown-preview + rust.vim | 原 3 个 spec + `config/MarkdownPreview.lua` |
| `lua/plugins/misc.lua` | faster.nvim + fidget.nvim | 原 2 个 spec |

**删除**：`lua/plugins.lua`、`lua/colorscheme.lua`、`lua/lsp.lua`、`lua/config/`（整个目录）。

---

## Task 1: 建立 plugins/ 目录骨架与新 init.lua

让 lazy 走 import 机制，但先只迁移最简单的 misc 插件，确保骨架跑通。

**Files:**
- Create: `lua/plugins/misc.lua`
- Modify: `init.lua`（整体改写）
- 暂不删除 `lua/plugins.lua` —— 本任务先让两者并存不可能（lazy 只能有一个 setup），所以本任务直接切换 init.lua 到新结构，并把**所有**原 spec 临时一次性迁出。

> **决策**：lazy.setup 只能调用一次。为避免中间状态下配置半丢失，本计划采用「一次性把全部 spec 迁到 plugins/ 目录，再切换 init.lua」的顺序：Task 1 建骨架 + misc，Task 2–13 逐个迁移其余插件到 `plugins/`（此时它们还没被加载，因为 init.lua 仍指向旧 `plugins.lua`），**Task 14 才切换 init.lua** 并删除旧文件。这样每个迁移任务都可独立加载检查，且随时可回滚。

- [ ] **Step 1: 创建 plugins/ 目录和 misc.lua**

Create `lua/plugins/misc.lua`：

```lua
-- 零/极简配置的小插件
return {
  -- Improve the performance of big file
  { "pteroctopus/faster.nvim" },

  -- LSP progress UI
  {
    "j-hui/fidget.nvim",
    opts = {
      -- options
    },
  },
}
```

- [ ] **Step 2: 加载检查 misc.lua**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.misc'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.misc')" -c "qa" 2>&1
```
Expected: 输出 `OK plugins.misc`，无报错。

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/misc.lua
git commit -m "refactor(plugins): add plugins/ dir with misc.lua (faster + fidget)"
```

---

## Task 2: 迁移 colorscheme

**Files:**
- Create: `lua/plugins/colorscheme.lua`
- Source: `lua/colorscheme.lua`（kanagawa setup）+ 原 `plugins.lua:16-21` 的 kanagawa spec

- [ ] **Step 1: 创建 plugins/colorscheme.lua**

把原 `lua/colorscheme.lua` 的 `require('kanagawa').setup({...})` 整段放进 `config`。注意原 colorscheme.lua 顶部还有两行 cursorline/cursorcolumn 设置——这两行属于 UI 选项而非 colorscheme，但原本就在该文件里执行，为保持行为一致一并放进 config。

```lua
return {
  "rebelot/kanagawa.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    -- open cursorline and cursorcolumn highlights
    vim.opt.cursorline = true
    vim.opt.cursorcolumn = true

    require('kanagawa').setup({
      compile = false,
      undercurl = true,
      commentStyle = { italic = true },
      functionStyle = {},
      keywordStyle = { italic = true },
      statementStyle = { bold = true },
      typeStyle = {},
      transparent = false,
      dimInactive = false,
      terminalColors = true,
      colors = {
        palette = {},
        theme = { wave = {}, lotus = {}, dragon = {}, all = {} },
      },
      overrides = function(colors)
        return {}
      end,
      theme = "wave",
      background = {
        dark = "wave",
        light = "lotus",
      },
    })

    vim.cmd("colorscheme kanagawa")
  end,
}
```

> 说明：`lazy = false` + `priority = 1000` 确保主题在启动时立即加载（colorscheme 惯例）。原配置在 init.lua 顶层 require，等价于启动即加载。

- [ ] **Step 2: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.colorscheme'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.colorscheme')" -c "qa" 2>&1
```
Expected: `OK plugins.colorscheme`

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/colorscheme.lua
git commit -m "refactor(plugins): migrate colorscheme (kanagawa) to plugins/"
```

---

## Task 3: 迁移 cmp（nvim-cmp + 依赖）

**Files:**
- Create: `lua/plugins/cmp.lua`
- Source: 原 `plugins.lua` 的 lspkind/nvim-cmp/LuaSnip spec + `lua/config/nvim-cmp.lua`

- [ ] **Step 1: 创建 plugins/cmp.lua**

把 lspkind、LuaSnip 作为 nvim-cmp 的相关项一起放本文件；`config` 内联原 `config/nvim-cmp.lua` 全文。

```lua
return {
  -- Vscode-like pictograms
  {
    "onsails/lspkind.nvim",
    event = { "VimEnter" },
  },

  -- Code snippet engine
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
  },

  -- Auto-completion engine
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "lspkind.nvim",
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
    },
    config = function()
      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end

      local luasnip = require("luasnip")
      local cmp = require("cmp")

      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-k>'] = cmp.mapping.select_prev_item(),
          ['<C-j>'] = cmp.mapping.select_next_item(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif has_words_before() then
              cmp.complete()
            else
              fallback()
            end
          end, { "i", "s" }),
          ["<S-Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_prev_item()
            elseif luasnip.jumpable(-1) then
              luasnip.jump(-1)
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        formatting = {
          fields = { 'abbr', 'menu' },
          format = function(entry, vim_item)
            vim_item.menu = ({
              nvim_lsp = '[Lsp]',
              luasnip = '[Luasnip]',
              buffer = '[File]',
              path = '[Path]',
            })[entry.source.name]
            return vim_item
          end,
        },
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
          { name = 'buffer' },
          { name = 'path' },
        })
      })
    end,
  },
}
```

- [ ] **Step 2: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.cmp'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.cmp')" -c "qa" 2>&1
```
Expected: `OK plugins.cmp`

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/cmp.lua
git commit -m "refactor(plugins): migrate nvim-cmp + lspkind + LuaSnip to plugins/"
```

---

## Task 4: 迁移并现代化 LSP（plugins/lsp.lua）

这是唯一涉及重写而非搬运的任务。把旧 `lua/lsp.lua` 重写为 0.11 `vim.lsp.config`/`vim.lsp.enable` + `LspAttach` autocmd 写法，删除死代码 `get_clangd_path()`。

**Files:**
- Create: `lua/plugins/lsp.lua`
- Source: `lua/lsp.lua`

- [ ] **Step 1: 创建 plugins/lsp.lua**

```lua
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
        ensure_installed = { 'lua_ls', 'pylsp' },
        automatic_installation = true,
      })

      -- ============ Diagnostics global keymaps ============
      local opts = { noremap = true, silent = true }
      vim.keymap.set('n', '<space>e', vim.diagnostic.open_float, opts)
      vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, opts)
      vim.keymap.set('n', ']d', vim.diagnostic.goto_next, opts)
      vim.keymap.set('n', '<space>q', vim.diagnostic.setloclist, opts)

      -- ============ Shared on-attach via LspAttach ============
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('UserLspConfig', {}),
        callback = function(ev)
          vim.api.nvim_buf_set_option(ev.buf, 'omnifunc', 'v:lua.vim.lsp.omnifunc')

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
          "/usr/bin/clangd",
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
```

> 行为对照：
> - **死代码 `get_clangd_path()` 已删除**；clangd 路径保留硬编码 `/usr/bin/clangd`（不变）。
> - 旧代码用 `root_dir = vim.fs.dirname(vim.fs.find({...}, {upward=true})[1])`；0.11 的 `vim.lsp.config` 用 `root_markers` 表达等价意图（nvim 自动向上查找）。各 server 的 marker 集合与旧代码 `vim.fs.find` 列表一一对应。
> - capabilities 由全局 `vim.lsp.config('*', ...)` 统一注入（旧代码只给了 clangd 显式 capabilities；现在所有 server 都拿到，这是改进且不破坏行为——cmp 补全在所有 server 上一致可用）。
> - 诊断快捷键、所有 buffer-local 快捷键逐条保留，仅从重复 `on_attach` 改为单个 `LspAttach` autocmd。

- [ ] **Step 2: 加载检查（spec 结构）**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.lsp'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.lsp')" -c "qa" 2>&1
```
Expected: `OK plugins.lsp`

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/lsp.lua
git commit -m "refactor(lsp): modernize to 0.11 vim.lsp.enable, drop get_clangd_path dead code"
```

---

## Task 5: 迁移 nvim-tree

**Files:**
- Create: `lua/plugins/nvim-tree.lua`
- Source: 原 spec + `lua/config/nvim-tree.lua`（121 行，含 on_attach 函数）

- [ ] **Step 1: 用 git mv 保留历史并改名**

```bash
git mv lua/config/nvim-tree.lua lua/plugins/nvim-tree.lua
```

- [ ] **Step 2: 把内容包裹成 spec**

打开 `lua/plugins/nvim-tree.lua`。当前文件以 `local is_ok, nvim_tree = pcall(require, "nvim-tree")` 开头、以 `nvim_tree.setup({...})` 结尾。把**整段已有内容**包进 spec 的 `config` 函数（保留原 `pcall` 守卫），并在顶部加上 spec 头：

```lua
return {
  "nvim-tree/nvim-tree.lua",
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  config = function()
    -- ↓↓↓ 原 config/nvim-tree.lua 全文原样粘贴于此（含 pcall 守卫、on_attach、setup 调用）↓↓↓
  end,
}
```

> 实现提示：原文件第 1–4 行的 `pcall` early-return 在 `config` 函数里仍然有效（`return` 直接退出该函数）。无需改动内部任何一行。

- [ ] **Step 3: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.nvim-tree'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.nvim-tree')" -c "qa" 2>&1
```
Expected: `OK plugins.nvim-tree`

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/nvim-tree.lua
git commit -m "refactor(plugins): migrate nvim-tree to plugins/ (inline config)"
```

---

## Task 6: 迁移 telescope

**Files:**
- Create: `lua/plugins/telescope.lua`
- Source: 原 spec + `lua/config/telescope.lua`

- [ ] **Step 1: 创建 plugins/telescope.lua**

```lua
return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    local is_ok, builtin = pcall(require, "telescope.builtin")
    if not is_ok then
      return
    end

    vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
    vim.keymap.set("n", "<leader>ft", builtin.git_files, {})
    vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
    vim.keymap.set("n", "<leader>fg", builtin.live_grep, {}) -- NOTE: requires ripgrep
    vim.keymap.set("n", "<leader>fc", function() -- fc = find by content
      builtin.grep_string({ search = vim.fn.input("rg > ") })
    end)

    -- 搜索当前光标的单词，精确匹配
    vim.keymap.set("n", "<leader>frb", function()
      local word = vim.fn.expand("<cword>")
      builtin.grep_string({ search = word, word_match = "-w" })
    end)

    -- 搜索当前光标的单词，模糊匹配
    vim.keymap.set("n", "<leader>frc", function()
      local word = vim.fn.expand("<cword>")
      builtin.grep_string({ search = word, use_regex = true })
    end)
  end,
}
```

- [ ] **Step 2: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.telescope'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.telescope')" -c "qa" 2>&1
```
Expected: `OK plugins.telescope`

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/telescope.lua
git commit -m "refactor(plugins): migrate telescope to plugins/ (inline config)"
```

---

## Task 7: 迁移 treesitter + textobjects（合一）

**Files:**
- Create: `lua/plugins/treesitter.lua`
- Source: 原 2 个 spec + `lua/config/nvim-treesitter.lua`（105 行）+ `lua/config/nvim-treesitter-textobjects.lua`（72 行）

- [ ] **Step 1: 创建 plugins/treesitter.lua 的 spec 骨架**

两个插件合到一个文件，作为两个独立 spec（textobjects 依赖 treesitter）。各自的 config 内联各自原文件全文。

```lua
return {
  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      -- ↓↓↓ 原 config/nvim-treesitter.lua 全文原样粘贴于此（含 pcall 守卫、configs.setup{...}）↓↓↓
    end,
  },

  -- Treesitter text objects
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    dependencies = "nvim-treesitter/nvim-treesitter",
    config = function()
      -- ↓↓↓ 原 config/nvim-treesitter-textobjects.lua 全文原样粘贴于此 ↓↓↓
    end,
  },
}
```

- [ ] **Step 2: 粘贴两份原 config 内容**

- 把 `lua/config/nvim-treesitter.lua` 第 1 行到结尾全文，粘进第一个 spec 的 config 函数体。
- 把 `lua/config/nvim-treesitter-textobjects.lua` 第 1 行到结尾全文，粘进第二个 spec 的 config 函数体。
- 两个原文件内部都以 `local is_ok, configs = pcall(require, "nvim-treesitter.configs")` 开头，`pcall` 守卫在 config 函数内仍有效，无需改动内部。

- [ ] **Step 3: 删除已迁移的旧 config 文件**

```bash
git rm lua/config/nvim-treesitter.lua lua/config/nvim-treesitter-textobjects.lua
```

- [ ] **Step 4: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.treesitter'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.treesitter')" -c "qa" 2>&1
```
Expected: `OK plugins.treesitter`

- [ ] **Step 5: Commit**

```bash
git add lua/plugins/treesitter.lua
git commit -m "refactor(plugins): merge treesitter + textobjects into plugins/treesitter.lua"
```

---

## Task 8: 迁移 aerial（400 行原样）

**Files:**
- Create: `lua/plugins/aerial.lua`
- Source: 原 spec + `lua/config/aerial.lua`（400 行）

- [ ] **Step 1: git mv 保留历史**

```bash
git mv lua/config/aerial.lua lua/plugins/aerial.lua
```

- [ ] **Step 2: 包裹成 spec**

打开 `lua/plugins/aerial.lua`。当前文件以 `require("aerial").setup({` 开头。在文件**最前面**插入 spec 头，把整段 `require("aerial").setup({...})` 包进 `config` 函数，文件末尾补上闭合：

```lua
return {
  "stevearc/aerial.nvim",
  dependencies = { "nvim-treesitter/nvim-treesitter", "neovim/nvim-lspconfig" },
  config = function()
    -- ↓↓↓ 原 config/aerial.lua 全文（400 行）原样保留于此 ↓↓↓
  end,
}
```

> 原 `plugins.lua` 中 aerial spec 有一个空的 `opts = {}`。`opts` 和 `config` 同时存在时，lazy 会先按 `opts` 调一次 `require('aerial').setup(opts)` 再调 `config`——这会导致 setup 被调两次。**不要保留 `opts = {}`**，只用 `config`（与原行为一致：原 `config` 函数本就显式调用 setup）。

- [ ] **Step 3: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.aerial'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.aerial')" -c "qa" 2>&1
```
Expected: `OK plugins.aerial`

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/aerial.lua
git commit -m "refactor(plugins): migrate aerial to plugins/ (config verbatim)"
```

---

## Task 9: 迁移 tagbar、easymotion、highlighter、bufferline

四个小插件，每个一个文件，结构同质。逐个做，每个独立 commit。

**Files:**
- Create: `lua/plugins/tagbar.lua`、`lua/plugins/easymotion.lua`、`lua/plugins/highlighter.lua`、`lua/plugins/bufferline.lua`

- [ ] **Step 1: 创建 plugins/tagbar.lua**

```lua
return {
  "preservim/tagbar",
  config = function()
    -- 设置 tagbar 子窗口出现在左边
    vim.g.tagbar_position = 'vertical topleft'
    vim.g.tagbar_left = 1
    vim.g.tagbar_width = 32
    vim.g.tagbar_compact = 1

    vim.g.tagbar_type_cpp = {
      kinds = {
        "c:classes:0:1", "d:macros:0:1", "e:enumerators:0:0",
        "f:functions:0:1", "g:enumeration:0:1", "l:local:0:1",
        "m:members:0:1", "n:namespaces:0:1", "p:functions_prototypes:0:1",
        "s:structs:0:1", "t:typedefs:0:1", "u:unions:0:1",
        "v:global:0:1", "x:external:0:1",
      },
      sro = "::",
      kind2scope = { g = "enum", n = "namespace", c = "class", s = "struct", u = "union" },
      scope2kind = { enum = "g", namespace = "n", class = "c", struct = "s", union = "u" },
    }

    vim.keymap.set("n", "<leader>ilt", "<cmd>TagbarToggle<CR>", { desc = "Toggle Tagbar" })
  end,
}
```

- [ ] **Step 2: 创建 plugins/easymotion.lua**

```lua
return {
  'easymotion/vim-easymotion',
  config = function()
    -- <Leader>f{char} 跳转到字符 {char}
    vim.api.nvim_set_keymap('n', '<Leader>s', '<Plug>(easymotion-bd-f)', { noremap = true, silent = true })
    vim.api.nvim_set_keymap('n', '<Leader>so', '<Plug>(easymotion-overwin-f)', { noremap = true, silent = true })

    -- s{char}{char} 跳转到字符 {char}{char}
    vim.api.nvim_set_keymap('n', '<Leader>ss', '<Plug>(easymotion-overwin-f2)', { noremap = true, silent = true })

    -- 跳转到行
    vim.api.nvim_set_keymap('n', '<Leader>L', '<Plug>(easymotion-bd-jk)', { noremap = true, silent = true })
    vim.api.nvim_set_keymap('n', '<Leader>L', '<Plug>(easymotion-overwin-line)', { noremap = true, silent = true })

    -- 跳转到单词
    vim.api.nvim_set_keymap('n', '<Leader>w', '<Plug>(easymotion-bd-w)', { noremap = true, silent = true })
    vim.api.nvim_set_keymap('n', '<Leader>w', '<Plug>(easymotion-overwin-w)', { noremap = true, silent = true })
  end,
}
```

- [ ] **Step 3: 创建 plugins/highlighter.lua**

```lua
return {
  "azabiong/vim-highlighter",
  config = function()
    vim.cmd([[
      let HiSet   = 'f<CR>'
      let HiErase = 'f<BS>'
      let HiClear = 'f<C-L>'
      let HiFind  = 'f<Tab>'
      let HiSetSL = 't<CR>'

      " jump key mappings
      nn n <Cmd>call HiSearch('n')<CR>
      nn N <Cmd>call HiSearch('N')<CR>

      " :noh command mapping, if there isn't
      nn <Esc>n <Cmd>noh<CR>
    ]])
  end,
}
```

- [ ] **Step 4: 创建 plugins/bufferline.lua**

```lua
return {
  'akinsho/bufferline.nvim',
  version = "*",
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  config = function()
    vim.opt.termguicolors = true
    require("bufferline").setup {
      options = {
        offsets = { {
          filetype = "NvimTree",
          text = "File Explorer",
          highlight = "Directory",
          text_align = "left",
        } },
        mode = "buffers",
        numbers = "ordinal",
        close_command = "bdelete! %d",
        right_mouse_command = "bdelete! %d",
        left_mouse_command = "buffer %d",
        middle_mouse_command = nil,
        indicator = { icon = '▎', style = 'icon' },
        buffer_close_icon = '',
        modified_icon = '●',
        close_icon = '',
        left_trunc_marker = '',
        right_trunc_marker = '',
        diagnostics = "nvim_lsp",
        separator_style = "slant",
        show_buffer_close_icons = true,
        show_close_icon = true,
        enforce_regular_tabs = false,
        always_show_bufferline = true,
        sort_by = 'insert_after_current',
      },
    }

    local map = vim.keymap.set
    map("n", "<Tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "next buffer" })
    map("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "before buffer" })

    for i = 1, 9 do
      map("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<CR>", { desc = "jump buffer" .. i })
    end
  end,
}
```

> 注意：bufferline 的 `<leader>1`..`<leader>9` 与 nvim-tree 等无冲突（保持原行为）；图标字形从原文件逐字复制，勿手敲。

- [ ] **Step 5: 逐个加载检查**

Run:
```bash
for m in tagbar easymotion highlighter bufferline; do
  nvim --headless -c "lua local ok,spec=pcall(require,'plugins.$m'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.$m')" -c "qa" 2>&1
done
```
Expected: 四行 `OK plugins.<name>`，无报错。

- [ ] **Step 6: Commit**

```bash
git add lua/plugins/tagbar.lua lua/plugins/easymotion.lua lua/plugins/highlighter.lua lua/plugins/bufferline.lua
git commit -m "refactor(plugins): migrate tagbar/easymotion/highlighter/bufferline to plugins/"
```

---

## Task 10: 修复并迁移 trouble（bug fix）

**Files:**
- Create: `lua/plugins/trouble.lua`
- Source: 原 `plugins.lua` trouble spec（`opts = function() require("config.trouble") end` 是错的）

- [ ] **Step 1: 创建 plugins/trouble.lua（修正 opts）**

原 spec 的 `keys` 表完整保留；把错误的 `opts = function() require("config.trouble") end` 改成 `opts = {}`（trouble 用默认配置即可——原本就没有有效的 config.trouble 文件，所以"正确行为"就是默认配置）。

```lua
return {
  "folke/trouble.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  opts = {},
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" },
    { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" },
    { "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>", desc = "Symbols (Trouble)" },
    { "<leader>cl", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP Definitions / references / ... (Trouble)" },
    { "<leader>xL", "<cmd>Trouble loclist toggle<cr>", desc = "Location List (Trouble)" },
    { "<leader>xQ", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix List (Trouble)" },
  },
}
```

- [ ] **Step 2: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.trouble'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.trouble')" -c "qa" 2>&1
```
Expected: `OK plugins.trouble`

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/trouble.lua
git commit -m "fix(trouble): use opts={} instead of broken require('config.trouble')"
```

---

## Task 11: 迁移 claude

**Files:**
- Create: `lua/plugins/claude.lua`
- Source: 原 spec + `lua/config/claude.lua`（62 行）

- [ ] **Step 1: git mv 保留历史**

```bash
git mv lua/config/claude.lua lua/plugins/claude.lua
```

- [ ] **Step 2: 包裹成 spec**

打开 `lua/plugins/claude.lua`。当前内容以 `require("claude-code").setup({...})` 开头（首行是空行，其后是 setup 调用）。在最前面插入 spec 头，把已有内容包进 config：

```lua
return {
  "greggh/claude-code.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    -- ↓↓↓ 原 config/claude.lua 全文（require("claude-code").setup({...})）原样保留于此 ↓↓↓
  end,
}
```

- [ ] **Step 3: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.claude'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.claude')" -c "qa" 2>&1
```
Expected: `OK plugins.claude`

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/claude.lua
git commit -m "refactor(plugins): migrate claude-code to plugins/ (inline config)"
```

---

## Task 12: 迁移 markdown（vim-markdown + markdown-preview + rust.vim）

三个相关插件合一。注意 markdown-preview 的 `init` 里原本有 `require("config.MarkdownPreview")`——这个 require 要改为内联。

**Files:**
- Create: `lua/plugins/markdown.lua`
- Source: 原 vim-markdown / markdown-preview / rust.vim 三个 spec + `lua/config/MarkdownPreview.lua`（112 行）

- [ ] **Step 1: git mv MarkdownPreview 内容到一个临时位置以便引用**

先把 `config/MarkdownPreview.lua` 的全文留作参考（下一步要内联进 `init`）。直接：

```bash
git mv lua/config/MarkdownPreview.lua lua/plugins/markdown.lua
```

- [ ] **Step 2: 重写 plugins/markdown.lua 为三 spec + 内联 init**

打开 `lua/plugins/markdown.lua`，当前是 MarkdownPreview 的一堆 `vim.g.mkdp_*` 设置。在文件顶部加 `return {`，把这些 `vim.g.mkdp_*` 设置放进 markdown-preview spec 的 `init` 函数体，并补上另外两个插件 spec。结构如下（`mkdp_*` 那一大段用文件里原有的全部内容替换占位注释）：

```lua
return {
  -- syntax highlighting and filetype plugins for Markdown
  {
    "tpope/vim-markdown",
    config = function()
      vim.g.markdown_syntax_conceal = 0
      vim.g.markdown_fenced_languages = {
        "html", "python", "bash=sh", "json", "java", "js=javascript",
        "sql", "yaml", "xml", "swift", "javascript", 'lua',
      }
    end,
  },

  -- Markdown preview in browser
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    build = "cd app && npm install",
    ft = { "markdown" },
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
      -- ↓↓↓ 原 config/MarkdownPreview.lua 的全部 vim.g.mkdp_* 设置原样粘贴于此 ↓↓↓
    end,
  },

  -- Rust syntax (also loaded for markdown per original config)
  {
    "rust-lang/rust.vim",
    ft = { "rust", "markdown" },
  },
}
```

> 行为对照：原 markdown-preview spec 的 `init` 里先 `vim.g.mkdp_filetypes = { "markdown" }` 再 `require("config.MarkdownPreview")`。现在把 `require` 换成把该文件内容直接内联——`vim.g.mkdp_filetypes` 仍在最前，其余 `mkdp_*` 设置顺序不变。

- [ ] **Step 3: 加载检查**

Run:
```bash
nvim --headless -c "lua local ok,spec=pcall(require,'plugins.markdown'); assert(ok, spec); assert(type(spec)=='table'); print('OK plugins.markdown')" -c "qa" 2>&1
```
Expected: `OK plugins.markdown`

- [ ] **Step 4: Commit**

```bash
git add lua/plugins/markdown.lua
git commit -m "refactor(plugins): merge vim-markdown + markdown-preview + rust.vim into plugins/markdown.lua"
```

---

## Task 13: 确认所有旧 config 文件已迁移

防止遗漏。此时 `lua/config/` 应已空（所有内容已迁出或 git rm/git mv）。

- [ ] **Step 1: 检查 config/ 残留**

Run:
```bash
ls -A lua/config/ 2>&1; echo "---"; git status --short
```
Expected: `lua/config/` 为空或不存在。若仍有文件，对照 File Structure 表确认它属于哪个已建的 `plugins/*.lua`，迁移后再继续。

- [ ] **Step 2: 删除空的 config/ 目录**

```bash
rmdir lua/config 2>/dev/null; echo done
```

- [ ] **Step 3: Commit（如有删除）**

```bash
git add -A lua/config 2>/dev/null
git commit -m "refactor: remove empty lua/config/ directory" 2>&1 || echo "nothing to commit"
```

---

## Task 14: 切换 init.lua 到 import 结构，删除旧入口文件

这是激活整个重构的关键任务。**做完这步前，新结构都不会被实际加载**。

**Files:**
- Modify: `init.lua`（整体改写）
- Delete: `lua/plugins.lua`、`lua/colorscheme.lua`、`lua/lsp.lua`

- [ ] **Step 1: 改写 init.lua**

```lua
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
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ============ Core settings ============
require("options")
require("keymaps")

-- ============ Plugins (auto-import lua/plugins/) ============
require("lazy").setup("plugins")
```

> 说明：colorscheme 和 lsp 不再在 init.lua 顶层 require——它们已是 `plugins/` 下的 spec，由 lazy 加载。`options`/`keymaps` 是纯 vim 设置，保留顶层 require。

- [ ] **Step 2: 删除旧入口文件**

```bash
git rm lua/plugins.lua lua/colorscheme.lua lua/lsp.lua
```

- [ ] **Step 3: 整体启动检查**

Run:
```bash
nvim --headless -c "lua print('loaded ' .. vim.tbl_count(require('lazy').plugins()) .. ' plugins')" -c "qa" 2>&1
```
Expected: 输出 `loaded N plugins`（N 应为所有 spec 数量，约 16+ 个含依赖），**无任何 Error / stack traceback**。

> 若报 `module 'plugins.X' not found` 或某 spec 报错，按错误信息定位对应文件修正后重跑。

- [ ] **Step 4: 启动健康检查**

Run:
```bash
nvim --headless -c "checkhealth lazy" -c "qa" 2>&1 | tail -30
```
Expected: lazy 健康检查无 ERROR（WARNING 可接受）。

- [ ] **Step 5: Commit**

```bash
git add init.lua lua/plugins.lua lua/colorscheme.lua lua/lsp.lua
git commit -m "refactor: switch init.lua to lazy import structure, remove old entry files"
```

---

## Task 15: 端到端验证

**Files:** 无（纯验证）

- [ ] **Step 1: 插件全量同步**

Run:
```bash
nvim --headless "+Lazy! sync" +qa 2>&1 | tail -20
```
Expected: 同步完成，无 spec 解析错误。

- [ ] **Step 2: 验证 LSP attach（Lua 文件）**

Run:
```bash
nvim --headless test_lsp.lua -c "lua vim.defer_fn(function() print('clients: ' .. vim.tbl_count(vim.lsp.get_clients({bufnr=0}))) ; vim.cmd('qa') end, 3000)" 2>&1 | tail -5
```
（若 `lua-language-server` 已装）Expected: 输出 `clients: 1` 或更多。若为 0，确认 lua_ls 已通过 mason 安装。

> 此步依赖外部 LSP 二进制已安装，可能因环境而异；若 LSP 未装，跳过此步并在最终报告中标注。

- [ ] **Step 3: 人工验证清单（交给用户在交互式 nvim 中确认）**

在最终报告中列出请用户手动确认的项：
- 打开任意文件，主题 kanagawa 正常显示。
- `<leader>ff` telescope 找文件；`<leader>xx` trouble 打开诊断面板（**这是修复点**）。
- 打开 .py/.c/.lua，LSP 补全与 `gd`/`K` 正常。
- 打开 .md，`:MarkdownPreview` 可用。
- `<Tab>`/`<S-Tab>` 切换 buffer（bufferline）。

- [ ] **Step 4: 最终 commit（如端到端中有微调）**

```bash
git add -A
git commit -m "refactor: finalize nvim config restructure" 2>&1 || echo "nothing to commit"
```

---

## 完成标准

- `lua/plugins/` 下每个插件一个文件，配置内联；`lua/config/`、`lua/plugins.lua`、`lua/colorscheme.lua`、`lua/lsp.lua` 已删除。
- LSP 用 0.11 `vim.lsp.config`/`vim.lsp.enable` + `LspAttach`；`get_clangd_path` 死代码已删。
- trouble 用 `opts = {}`，`<leader>xx` 等快捷键可用（bug 修复）。
- `nvim --headless "+Lazy! sync" +qa` 与启动均无报错。
- 除 trouble 修复外，所有快捷键与插件行为与重构前等价。
