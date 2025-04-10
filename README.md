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

   - If you want the **stable release**, also run `git checkout stable`.OR`git checkout v0.10.3`目前使用的是V0.10.3

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

首先看下按照本篇教程配置 `Nvim` 之后，目录结构看起来会是怎么样⬇️

```
.
├── init.lua
└── lua
    ├── colorscheme.lua
    ├── keymaps.lua
    ├── lsp.lua
    ├── options.lua
    └── plugins.lua
```

**解释如下**

-  `init.lua`为`Nvim`配置的 Entry point，我们主要用来导入其他 `*.lua` 文件
  - `colorscheme.lua` 配置主题
  - `keymaps.lua` 配置按键映射
  - `lsp.lua` 配置 LSP
  - `options.lua` 配置选项
  - `plugins.lua` 配置插件
- `lua`目录。当我们在 Lua 里面调用`require`加载模块（文件）的时候，它会自动在`lua`文件夹里面进行搜索
  - *将路径分隔符从 `/` 替换为 `.`，然后去掉 `.lua` 后缀就得到了 `require` 的参数格式*

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

新建 `~/.config/nvim/lua/plugins.lua` 文件并放入如下内容。下面的模板只完成了 `lazy.nvim` 自身的安装，**还没有指定其他第三方插件**

```lua
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

require("lazy").setup({})
```

在 `lazy.nvim` 指定第三方插件很简单，只需要在 `require("lazy").setup({ ... })` 的 `...` 里面声明插件

然后在 `init.lua` 文件里面再次加上一行导入这个文件

```lua
... -- 省略其他行
require('plugins')
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

### 自动补全插件

**Warning**

[blink.cmp](https://github.com/saghen/blink.cmp) 还在 beta 版本，这意味着变动会比较大，而且可能会遇到不少 Bug。但我目前日常使用下来没有问题 :)

​	之前本文的自动补全插件采用的是 [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)，但配置上较为繁琐。现在有了 [blink.cmp](https://github.com/saghen/blink.cmp) 插件，*配置会比较简单而且自动补全特别快*

在 `plugins.lua`里新增这个插件并做好配置

关注其中的 `opts` 配置选项即可，关键的几个*解释如下*

Key用于配置按键映射，格式也很好理解

- `preset = "enter"` 表示用 `回车键` 确定当前选中的补全项
- `select_prev, select_next` 用于在各个候选项中进行选择，我这里配置了 2 套按键，支持用⬆️/⬇️，或者用 Tab/Shift-Tab 进行补全项的选择
- `scroll_documentation_up, scroll_documentation_down` 用于滚动 API 的文档，我配置的是 `Ctrl-b, Ctrl-f`

- `trigger = { show_on_trigger_character = true }` - 输入字符之后就会展示所有可用补全项
- `documentation = { auto_show = true }` - 自动显示当前被选中补全项的文档

> 🎙️ 到这为止，重新启动 `Nvim` 后，等待插件安装完成后应该就能够用初步的自动补全功能了～

### LSP 配置

​	要把 `Nvim` 变成 IDE 就势必要借助于 LSP[3](https://martinlwx.github.io/zh-cn/config-neovim-from-scratch/#fn:3)，自己安装和配置 LSP 是比较繁琐的。不同的 LSP 安装方法不同，也不方便后续管理。[mason.nvim](https://github.com/williamboman/mason.nvim) 和配套的 [mason-lspconfig.nvim](https://github.com/williamboman/mason-lspconfig.nvim) 这两个插件很好解决了这个问题 

首先修改 `plugins.lua` 文件，增加对应的插件

```
... -- 省略其他行
require("lazy").setup({
	-- LSP manager
	"williamboman/mason.nvim",
	"williamboman/mason-lspconfig.nvim",
	"neovim/nvim-lspconfig",
    ... -- 省略其他行
})
```

新建一个 `~/.config/nvim/lua/lsp.lua` 文件并编辑，首先配置 `mason` 和 `mason-lspconfig`

```
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
    -- A list of servers to automatically install if they're not already installed
    ensure_installed = { 'pylsp', 'lua_ls', 'rust_analyzer' },
})
```

> 💡 我们想要用什么语言的 LSP 就在 `ensure_installed` 里面加上，完整的列表可以看 [server_configurations](https://github.com/neovim/nvim-lspconfig/blob/master/doc/server_configurations.md)。我个人常用的就 `python/rust` 这两个编程语言，而因为我们都用 Lua 语言来配置 `Nvim`，所以也加上了 `lua_ls`

配置好 `mason-lspconfig` 之后，接下来就可以配置 `nvim-lspconfig` 了。因为配置的代码比较长，下面只展示了 `pylsp` 的配置，其他语言的配置大同小异。如果有疑惑，可以查看该文件的[最新版本](https://github.com/MartinLwx/dotfiles/blob/main/nvim/lua/lsp.lua)

> 💡 每个 LSP 都存在自己可以配置的选项，你可以自己去对应 LSP 的 GitHub 仓库查阅更多信息。如果要用默认配置的话，基本上每一个新的语言都只需要设置 `on_attach = on_attach`

编辑 `~/.config/nvim/lua/lsp.lua` 文件新增如下内容上面的按键绑定的意思是很直观的，这里就不多解释啦最后在 `init.lua` 文件里面加上

```
... -- 省略其他行
require('lsp')
```

​	重启 `Nvim` 之后，你应该可以在下面的状态栏看到 `Mason` 正在下载并安装前面我们指定的 LSP（**注意此时不能关闭 `Nvim`**），可以输入 `:Mason` 查看安装进度。在你等待安装的过程中，可以输入 `g?` 查看更多帮助信息了解如何使用 `mason` 插件



TO DO ...

# [REF]

- [use_vim_as_ide](https://github.com/yangyangwithgnu/use_vim_as_ide)
- [从零开始配置 Neovim(Nvim)](https://martinlwx.github.io/zh-cn/config-neovim-from-scratch/#%E4%B8%BA%E4%BB%80%E4%B9%88%E9%80%89%E6%8B%A9-neovim)

