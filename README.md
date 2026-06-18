[Toc]

# 版本信息

主要开发环境是Ubuntu

```shell
PRETTY_NAME="Ubuntu 22.04.4 LTS"
NAME="Ubuntu"
VERSION_ID="22.04"
VERSION="22.04.4 LTS (Jammy Jellyfish)"
VERSION_CODENAME=jammy
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=jammy
```

# 为什么选择 Neovim

​	在使用 `Vim` 两年多之后，我越发觉得 `Vim` 的配置麻烦，启动加载速度也不尽人意。我也很不喜欢 Vimscript 的写法，最主要的原因是AI编程大爆发，``Vim``无法和copilot直接交互，这导致我决定使用 `Neovim(Nvim)`。我决定**重新配置** `Nvim`。为什么会想要**重新配置**而不是**迁移配置**呢？因为我想顺便趁着这个机会，**重新审视**我本来 `Vim` 的配置Keep simple.

---

# 1、源码安装编辑器 Nvim

​	发行套件的软件源中预编译的 Nvim 要么不是最新版本，要么功能有阉割，有必要升级成全功能的最新版，可以通过源码安装：Install build prerequisites on your system

1. Install [build prerequisites](https://github.com/neovim/neovim/blob/master/BUILD.md#build-prerequisites) on your system

2. `git clone https://github.com/neovim/neovim`

3. ```
   cd neovim
   ```

   - If you want the **stable release**, also run `git checkout stable`.OR`git checkout NVIM v0.12.3`
4. ```
   make CMAKE_BUILD_TYPE=RelWithDebInfo
   ```

   - If you want to install to a custom location, set `CMAKE_INSTALL_PREFIX`. See also [INSTALL.md](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-source).
   - On BSD, use `gmake` instead of `make`.
   - To build on Windows, see the [Building on Windows](https://github.com/neovim/neovim/blob/master/BUILD.md#building-on-windows) section. *MSVC (Visual Studio) is recommended.*

5. ```
   sudo make install
   ```

   - Default install location is `/usr/local`
   - On Debian/Ubuntu, instead of `sudo make install`, you can try `cd build && cpack -G DEB && sudo dpkg -i nvim-linux-<arch>.deb` (with `<arch>` either `x86_64` or `arm64`) to build DEB-package and install it. This helps ensure clean removal of installed files. Note: This is an unsupported, "best-effort" feature of the Nvim build.

## Nvim 配置基础知识

### Lua 语言

在配置 `Nvim` 的时候，我会**尽可能**用 Lua 语言写配置，因此你有必要了解一下 Lua 的基本语法和语义。可以快速浏览一下 [Learn Lua in Y minutes](https://learnxinyminutes.com/docs/lua/) 了解大概

### 配置文件路径

`Nvim` 的配置目录在 `~/.config/nvim` 下。在 Linux/Mac 系统上，`Nvim` 会默认读取 `~/.config/nvim/init.lua` 文件，**理论上**来说可以将所有配置的东西都放在这个文件里面，但这样不是一个好的做法，因此我划分不同的文件和目录来分管不同的配置

首先看下当前配置的目录结构看起来会是怎么样⬇️

```
.
├── init.lua                # 入口：mapleader → lazy.nvim 引导 → require options/keymaps → lazy.setup("plugins")
├── lua
│   ├── options.lua         # vim 选项
│   ├── keymaps.lua         # 全局按键映射（含 Copilot 等无独立插件 spec 的快捷键）
│   └── plugins/            # 插件目录，lazy.nvim 通过 import 自动加载本目录下每个文件
│       ├── colorscheme.lua # kanagawa 主题
│       ├── lsp.lua         # mason + mason-lspconfig + nvim-lspconfig（Neovim 0.11 写法）
│       ├── cmp.lua         # nvim-cmp + lspkind + LuaSnip + cmp-* 依赖
│       ├── treesitter.lua  # nvim-treesitter + treesitter-textobjects
│       ├── telescope.lua   # 模糊查找
│       ├── nvim-tree.lua   # 文件树
│       ├── aerial.lua      # 代码大纲
│       ├── tagbar.lua      # 基于标签的标识符列表
│       ├── gtags.lua       # cscope/gtags 符号跳转（cscope_maps.nvim）
│       ├── trouble.lua     # 诊断/引用列表
│       ├── bufferline.lua  # 顶部 buffer 标签栏
│       ├── easymotion.lua  # 快速移动
│       ├── highlighter.lua # vim-highlighter
│       ├── markdown.lua    # vim-markdown + markdown-preview + rust.vim
│       ├── claude.lua      # claudecode.nvim（AI 编程）
│       └── misc.lua        # faster.nvim + fidget.nvim 等零/极简配置的小插件
├── claude                  # Claude Code 相关配置（见下文 CLAUDE 章节）
└── lazy-lock.json          # lazy.nvim 锁定的插件版本
```

**解释如下**

-  `init.lua` 为 `Nvim` 配置的 Entry point。它负责设置 `mapleader`、引导（bootstrap）`lazy.nvim`、`require('options')` / `require('keymaps')`，最后用 `require("lazy").setup("plugins")` 一行加载整个 `lua/plugins/` 目录
- `lua/options.lua` 配置选项，`lua/keymaps.lua` 配置全局按键映射
- `lua/plugins/` 目录采用**「每个插件一个文件」**的约定：每个 `*.lua` 文件 `return` 一个（或一组相关的）插件 spec，配置代码内联到 spec 的 `config` / `opts` / `init` 字段，不再有独立的 `config/` 目录。`lazy.nvim` 会通过 `import` 自动扫描并加载本目录下的所有文件
- `lua`目录。当我们在 Lua 里面调用`require`加载模块（文件）的时候，它会自动在`lua`文件夹里面进行搜索
  - *将路径分隔符从 `/` 替换为 `.`，然后去掉 `.lua` 后缀就得到了 `require` 的参数格式*

> 📌 这是一次结构重构的结果。早先的配置把所有插件 spec 堆在单个 `lua/plugins.lua` 里，并用 `lua/config/*.lua` 存放每个插件的配置；现在统一改成 `lua/plugins/` 下「每插件一文件、配置内联」的组织方式，`colorscheme` 和 `lsp` 也都作为普通插件 spec 进入该目录、由 lazy 加载，不再在 `init.lua` 顶层 `require`。

### 选项配置

主要用到的就是 `vim.g`、`vim.opt`、`vim.cmd` 等，我制造了一个快速参照对比的表格

| In `Vim`          | In `Nvim`                 | Note                             |
| ----------------- | ------------------------- | -------------------------------- |
| `let g:foo = bar` | `vim.g.foo = bar`         |                                  |
| `set foo = bar`   | `vim.opt.foo = bar`       | `set foo` = `vim.opt.foo = true` |
| `some_vimscript`  | `vim.cmd(some_vimscript)` |                                  |

### 按键配置

在 `Nvim` 里面进行按键绑定的语法如下，具体的解释可以看 `:h vim.keymap.set`

```lua
vim.keymap.set(<mode>, <key>, <action>, <opts>)
```

# 2、插件管理

## 安装插件管理器

一个强大的 `Nvim` 离不开插件的支持。我选用的是当下最为流行 [lazy.nvim](https://github.com/folke/lazy.nvim)。它支持如下许多特性：

- 正确处理不同插件之间的依赖
- 支持定制 Lazy loading，比如基于 Event、Filetype 等
- …

`lazy.nvim` 自身的引导（bootstrap）逻辑直接放在 `init.lua` 顶部。下面的模板完成 `lazy.nvim` 的自动安装，并通过 `import` 加载 `lua/plugins/` 整个目录

```lua
-- ~/.config/nvim/init.lua
vim.g.mapleader = ' '   -- 必须在加载插件之前设置

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

-- ============ Plugins（自动 import lua/plugins/ 目录）============
require("lazy").setup("plugins")
```

关键在于最后一行 `require("lazy").setup("plugins")`：传入字符串 `"plugins"` 时，`lazy.nvim` 会 `import` 整个 `lua/plugins/` 目录，自动收集每个文件 `return` 的插件 spec。这样新增一个插件只需在 `lua/plugins/` 下新建一个 `.lua` 文件，无需改动 `init.lua`

每个插件文件形如：

```lua
-- lua/plugins/telescope.lua
return {
  'nvim-telescope/telescope.nvim',
  dependencies = { 'nvim-lua/plenary.nvim', 'nvim-treesitter/nvim-treesitter' },
  config = function()
    require('telescope').setup({ --[[ 配置内联在此 ]] })
  end,
}
```

## 代码分析

### 语义系统

​	通过 ctags 这类标签系统在一定程度上助力 vim 理解我们的代码，对于 C 语言这类简单语言来说，差不多也够了。近几年，随着 C++11/14 的推出，诸如类型推导、lamda 表达式、模版等等新特性，标签系统显得有心无力，这个星球最了解代码的工具非编译器莫属，如果编译器能在语义这个高度帮助 vim 理解代码，那么我们需要的各项 IDE 功能肯定能达到另一个高度。

语义系统，编译器必不可少。GCC 和 clang 两大主流 C/C++ 编译器，作为语义系统的支撑工具，我选择后者，除了 clang 对新标准支持及时、错误诊断信息清晰这些优点之外，更重要的是，它在高内聚、低耦合方面做得非常好，各类插件可以调用 libclang 获取非常完整的代码分析结果，从而轻松且优雅地实现高阶 IDE 功能。你对语义系统肯定还是比较懵懂，紧接着的“基于语义的声明/定义跳转”会让你有更为直观的了解，现在，请跳转至“7.1 编译器/构建工具集成”，一是了解 clang 相较 GCC 的优势，二是安装好最新版 clang 及其标准库，之后再回来。

### 基于标签的标识符列表

在阅读代码时，经常分析指定函数实现细节，我希望有个插件能把从当前代码文件中提取出的所有标识符放在一个侧边子窗口中，并且能能按语法规则将标识符进行归类，tagbar （https://github.com/majutsushi/tagbar ）是一款基于标签的标识符列表插件，它自动周期性调用 ctags 获取标签信息（仅保留在内存，不落地成文件）。安装完 tagbar 后，

------

#### 推荐用 `universal-ctags`

如果你希望用功能更强、更新更频繁的版本，可以选择 Universal Ctags：

```bash
sudo apt remove exuberant-ctags
git clone https://github.com/universal-ctags/ctags.git
cd ctags
./autogen.sh
./configure
make
sudo make install
```

之后再运行：

```bash
ctags --version
```

你应该会看到：

```
Universal Ctags ...
```

### 大型代码库符号跳转（gtags / cscope）

对于内核、大型 C/C++ 工程，仅靠 LSP 索引可能力不从心。这里用 GNU GLOBAL（gtags）建立全局索引，并通过 [cscope_maps.nvim](https://github.com/dhananjaylatkar/cscope_maps.nvim) 的 cscope 接口做符号跳转，跳转结果走 telescope 展示。配置在 `lua/plugins/gtags.lua`

前置依赖与建索引：

```bash
sudo apt install global            # 提供 gtags / global / gtags-cscope

# 在工程根目录建索引（建好后会生成 GTAGS / GRTAGS / GPATH 三个文件）
gtags                              # 普通工程
make gtags                         # Linux 内核源码（自带 target）
```

> 💡 这里**刻意不用** `vim-gutentags` 自动维护索引：它的 cscope_maps 桥接会把 db 路径劫持到 `~/.cache/gutentags` 下，对超大代码库（如内核）容易建索引失败而导致查询永远为空。改为手动在源码树里建 `GTAGS`，索引改动后按 `<leader>gb` 手动重建。

### 自动补全插件

自动补全采用 [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)，配置内联在 `lua/plugins/cmp.lua`，组合了以下几个组件：

- `hrsh7th/nvim-cmp` —— 补全引擎本体
- `L3MON4D3/LuaSnip` —— 代码片段（snippet）引擎
- `onsails/lspkind.nvim` —— VSCode 风格的补全图标
- 补全来源：`cmp-nvim-lsp`（LSP）、`cmp-buffer`（当前缓冲区）、`cmp-path`（路径）、`cmp-cmdline`（命令行）

补全所需的 capabilities 在 `lua/plugins/lsp.lua` 里通过 `cmp_nvim_lsp.default_capabilities()` 设置（见上文 LSP 章节），两者协同工作

> 🎙️ 到这为止，重新启动 `Nvim` 后，等待插件安装完成后应该就能够用初步的自动补全功能了～

### LSP 配置

​	要把 `Nvim` 变成 IDE 就势必要借助于 LSP[3](https://martinlwx.github.io/zh-cn/config-neovim-from-scratch/#fn:3)，自己安装和配置 LSP 是比较繁琐的。不同的 LSP 安装方法不同，也不方便后续管理。[mason.nvim](https://github.com/williamboman/mason.nvim) 和配套的 [mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim) 这两个插件很好解决了这个问题。LSP 的全部声明与配置都内联在 `lua/plugins/lsp.lua` 这一个文件里

整个 spec 包含 `mason.nvim`、`mason-lspconfig.nvim`、`nvim-lspconfig`（以及给 capabilities 用的 `cmp-nvim-lsp`），在 `config` 函数里完成全部设置：

```lua
-- lua/plugins/lsp.lua（节选）
require('mason').setup({
  ui = { icons = { package_installed = "✓", package_pending = "➜", package_uninstalled = "✗" } },
})

require('mason-lspconfig').setup({
  -- clangd 的预编译二进制不支持 aarch64（树莓派），改用系统包 /usr/bin/clangd
  ensure_installed = { 'lua_ls', 'pylsp' },
  automatic_installation = false,
})
```

> 💡 我们想要用什么语言的 LSP 就在 `ensure_installed` 里面加上，完整的列表可以看 [server_configurations](https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md)。这里常用的就 `python`（pylsp）和配置 Nvim 用的 `lua_ls`；`clangd` 因为在 aarch64（树莓派）上没有预编译二进制，改用系统包管理器安装的 `/usr/bin/clangd`，直接走 PATH 而不经过 mason

**Neovim 0.11 原生 LSP 写法**：不再为每个 server 手写 `on_attach`，而是用 `vim.lsp.config` 声明配置、`vim.lsp.enable` 启用，再用一个 `LspAttach` autocmd 统一设置所有 buffer-local 快捷键

```lua
-- 全局 capabilities（来自 cmp-nvim-lsp），只设一次
local capabilities = require("cmp_nvim_lsp").default_capabilities()
capabilities.offsetEncoding = { "utf-16" }
vim.lsp.config('*', { capabilities = capabilities })

-- 各 server 声明
vim.lsp.config('pylsp',  { cmd = { "pylsp" }, filetypes = { "python" }, ... })
vim.lsp.config('clangd', { cmd = { "clangd", "--background-index", ... }, filetypes = { "c", "cpp", ... } })
vim.lsp.config('lua_ls', { cmd = { "lua-language-server" }, settings = { Lua = { ... } } })

-- 一行启用，nvim 按 filetype 自动启动对应 server
vim.lsp.enable({ 'pylsp', 'clangd', 'lua_ls' })

-- 统一的 buffer-local 快捷键（gD/gd/K/gi/<space>rn/<space>ca/gr/<space>f 等）
vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('UserLspConfig', {}),
  callback = function(ev)
    local bufopts = { noremap = true, silent = true, buffer = ev.buf }
    vim.keymap.set('n', 'gd', vim.lsp.buf.definition, bufopts)
    vim.keymap.set('n', 'K',  vim.lsp.buf.hover, bufopts)
    -- ... 其余快捷键同理
  end,
})
```

> 💡 因为这是一个普通的插件 spec，放在 `lua/plugins/lsp.lua` 后由 lazy.nvim 自动加载，**不需要**再在 `init.lua` 里手动 `require('lsp')`

​	重启 `Nvim` 之后，你应该可以在下面的状态栏看到 `Mason` 正在下载并安装前面我们指定的 LSP（**注意此时不能关闭 `Nvim`**），可以输入 `:Mason` 查看安装进度。在你等待安装的过程中，可以输入 `g?` 查看更多帮助信息了解如何使用 `mason` 插件


### **HOWTO Use Clangd in Nvim**
    如何使用LSP在设置的clangd这个工具后，需要配合bear来生成编译文件，clangd根据这个来跳转。
```shell
    Bear is a tool to generate a compile_commands.json file by recording a complete build.
For a make-based build, you can run make clean; bear -- make to generate the file (and run a clean build!).
```
https://clangd.llvm.org/installation.html#project-setup

Clangd and compile_commands.json
If it is C repo, the file compile_commands.json is needed for language server 'clangd' to work.

Linux Kernel
Run 'scripts/clang-tools/gen_compile_commands.py' after kernel compiling. This will generate compile_commands.json in the top directory.

After that, editing c file in the kernel repo will make clangd start to act as a language server.

# CLAUDE

将 `claude/` 目录下的配置文件放入 `~/.claude/` 目录下。其中包含：

- `settings.json` —— Claude Code 设置
- `statusline-command.sh` —— 自定义状态栏脚本，显示模型、reasoning effort、上下文窗口占用进度条与 token 使用量，以及 5 小时速率限制用量

编辑器内的 Claude Code 集成由 [claudecode.nvim](https://github.com/coder/claudecode.nvim) 提供（配置见 `lua/plugins/claude.lua`）。

# [REF]

- [use_vim_as_ide](https://github.com/yangyangwithgnu/use_vim_as_ide)
- [从零开始配置 Neovim(Nvim)](https://martinlwx.github.io/zh-cn/config-neovim-from-scratch/#%E4%B8%BA%E4%BB%80%E4%B9%88%E9%80%89%E6%8B%A9-neovim)

