# Neovim 配置重构设计

日期：2026-06-16

## 目标

让现有 Neovim 配置更清晰，具体三个方向：

1. **拆分 `lua/plugins.lua`** — 把 237 行的单文件插件清单按「每插件一文件」拆开。
2. **统一配置组织约定** — 用 lazy.nvim 的 `import` 机制，每个插件一个 `.lua`，配置内联进 spec，删除 `lua/config/` 目录。
3. **现代化 LSP 配置** — 用 Neovim 0.11 的 `vim.lsp.config` + `vim.lsp.enable` 写法，去掉重复的 `on_attach`。

**总原则：不改变任何现有行为**（唯一例外见下文 trouble 修复），只重组结构、现代化 LSP、清理死代码。

环境：Neovim v0.11.5。

## 现状

```
init.lua                  → require plugins / colorscheme / lsp / keymaps / options
lua/plugins.lua           → lazy.nvim setup，所有插件 spec 堆在一个文件（237 行）
lua/options.lua           → vim 选项
lua/keymaps.lua           → 全局快捷键（含 Copilot）
lua/colorscheme.lua       → kanagawa 配置
lua/lsp.lua               → mason + 3 个 LSP（pylsp/clangd/lua_ls），手写 on_attach
lua/config/*.lua          → 每个插件一个配置文件（12 个）
```

### 现状的具体问题

1. `plugins.lua` 把插件声明和配置逻辑混在一起（如 vim-markdown 的 `vim.g` 设置），文件长、难扫读。
2. `lua/lsp.lua` 用旧写法（手写 `vim.lsp.config[...]` + `vim.lsp.start`），每个 server 重复 `on_attach`。
3. **死代码**：`lua/lsp.lua` 中 `get_clangd_path()` 定义了但从未被调用（clangd 实际用硬编码 `{ "/usr/bin/clangd" }`）。
4. **Bug**：`plugins.lua` 中 `require("config.trouble")` 引用了不存在的文件 `lua/config/trouble.lua`；且其 spec 写成 `opts = function() require(...) end`，`opts` 应返回 table，写法错误，导致 trouble.nvim 未被正确配置。

## 目标结构

```
init.lua            -- mapleader → lazy bootstrap → require('options')/require('keymaps') → lazy.setup('plugins')
lua/
  options.lua       -- 不变
  keymaps.lua       -- 不变（Copilot 等无对应插件 spec 的全局快捷键保留在此）
  plugins/          -- lazy 通过 import 自动加载本目录
    colorscheme.lua -- kanagawa（含原 colorscheme.lua 的 setup）
    cmp.lua         -- nvim-cmp + lspkind + LuaSnip + cmp-* 依赖
    lsp.lua         -- mason + mason-lspconfig + nvim-lspconfig（0.11 写法）
    nvim-tree.lua
    telescope.lua
    treesitter.lua  -- nvim-treesitter + nvim-treesitter-textobjects 合一
    aerial.lua
    tagbar.lua
    easymotion.lua
    highlighter.lua -- vim-highlighter
    bufferline.lua
    trouble.lua     -- 修复缺失文件的 bug
    claude.lua
    markdown.lua    -- vim-markdown + markdown-preview.nvim + rust.vim 的 markdown 部分
    misc.lua        -- faster.nvim + fidget.nvim（零/极简配置的小插件）
```

**删除**：`lua/config/`（整个目录）、`lua/plugins.lua`、`lua/colorscheme.lua`、`lua/lsp.lua`（内容均迁移到 `lua/plugins/`）。

### 合并决策

- treesitter + textobjects 合并为 `treesitter.lua`。
- colorscheme（kanagawa）作为一个插件进 `plugins/`。
- faster.nvim 与 fidget.nvim 合并进 `misc.lua`。
- vim-markdown + markdown-preview.nvim + rust.vim 合并进 `markdown.lua`。

## 配置组织约定

- 每个 `plugins/*.lua` 文件 `return { ... }` 一个（或一组相关）插件 spec。
- 配置代码内联到 spec 的 `config` / `opts` / `init` 字段，不再有独立 `config/` 目录。
- 例外：aerial 的配置约 400 行（大部分是抄录的默认值），**原样全部保留**，整段放进 `plugins/aerial.lua` 的 `config` 函数，不删减、不改行为。

示例形态：

```lua
-- lua/plugins/telescope.lua
return {
  'nvim-telescope/telescope.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'nvim-treesitter/nvim-treesitter' },
  config = function()
    require('telescope').setup({ --[[ 原 config/telescope.lua 内容 ]] })
  end,
}
```

## LSP 现代化（`lua/plugins/lsp.lua`）

采用 Neovim 0.11 原生写法：

- spec 包含 mason.nvim、mason-lspconfig.nvim、nvim-lspconfig。
- `vim.lsp.config('*', { capabilities = ... })` 设置全局 capabilities（来自 `cmp_nvim_lsp`），去掉每个 server 重复设置。
- `vim.lsp.config('pylsp', {...})`、`vim.lsp.config('clangd', {...})`、`vim.lsp.config('lua_ls', {...})` 分别声明各 server。
  - clangd 保留硬编码路径 `/usr/bin/clangd`（这是用户先前 commit 有意为之，不改）。
  - 保留各 server 现有的 `cmd` / `filetypes` / `root_dir` / `settings`。
- `vim.lsp.enable({ 'pylsp', 'clangd', 'lua_ls' })` 一行启用，nvim 按 filetype 自动启动，不再手写 `vim.lsp.start`。
- 用一个 `LspAttach` autocmd 统一设置所有 buffer-local 快捷键（`gD`/`gd`/`K`/`gi`/`<C-k>`/`<space>wa`/`<space>wr`/`<space>wl`/`<space>D`/`<space>rn`/`<space>ca`/`gr`/`<space>f` 等），取代重复的 `on_attach`。
- 诊断全局快捷键（`<space>e`/`[d`/`]d`/`<space>q`）保留。
- mason / mason-lspconfig 的 `ensure_installed`、`ui.icons` 等设置保留。
- **删除死代码** `get_clangd_path()`。

## Bug 修复（`lua/plugins/trouble.lua`）

- 新建 `plugins/trouble.lua`，将原 `plugins.lua` 中 folke/trouble.nvim 的 `keys` 表完整搬入。
- 把错误的 `opts = function() require("config.trouble") end` 改为正确的 `opts = {}`（或返回 table 的函数）。
- 这是**唯一会改变运行时行为**的地方：修复前 trouble.nvim 因 `config.trouble` 文件不存在而报错/未正确配置；修复后按预期工作。

## init.lua 改动

```lua
vim.g.mapleader = ' '

-- lazy.nvim bootstrap（从原 plugins.lua 顶部完整迁移：clone lazypath + prepend rtp）
-- 必须在 require('lazy') 之前执行
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  -- ...原 plugins.lua 顶部的 git clone 逻辑...
end
vim.opt.rtp:prepend(lazypath)

require('options')
require('keymaps')
require('lazy').setup('plugins')   -- import 整个 lua/plugins/ 目录
```

colorscheme、lsp 不再在 init.lua 顶层 require —— 它们成为 `plugins/` 下的插件 spec，由 lazy 加载。

> 注：`keymaps.lua` 中的 Copilot 快捷键（`<M-l>` / `<M-i>`）引用的 copilot 插件**当前并未在 `plugins.lua` 中声明**（可能是手动安装或历史遗留）。本次重构保持现状，不新增也不删除该插件声明，相关快捷键原样留在 `keymaps.lua`。

## 验证方式

本项目无测试套件，验证以「加载无错」为准：

1. **逐文件**：每迁移/新建一个 `plugins/*.lua`，用 `nvim --headless` 加载该模块，确认无语法/运行错误。
2. **整体**：全部完成后运行
   - `nvim --headless "+Lazy! sync" +qa` — 确认插件清单解析无误、无加载错误。
   - 启动 nvim 后 `:checkhealth`，确认无新增报错。
   - 手动抽查：打开一个 .py / .c / .lua 文件确认 LSP 正常 attach；打开 .md 确认 markdown 相关插件加载；`<leader>xx` 确认 trouble 可用。

## 不做的事（YAGNI / 越界）

- 不删减 aerial 的默认值配置（用户选择原样保留）。
- 不动 `options.lua` / `keymaps.lua` 里用户有意留下的注释掉的配置。
- 不改 LSP server 的任何行为参数（路径、filetypes、settings 等）。
- 不引入新插件、不做与本次目标无关的重构。
