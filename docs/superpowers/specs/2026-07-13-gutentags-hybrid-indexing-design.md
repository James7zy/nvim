# Neovim Gutentags 混合索引设计

日期：2026-07-13

状态：已批准

## 目标

把《Vim 8 中 C/C++ 符号索引：GTags 篇》的核心工作流集成到当前 Neovim 配置：普通项目由 Gutentags 在后台维护 GNU GLOBAL 数据库，大型项目继续使用项目内手动维护的 `GTAGS`，两种模式共用相同的查询键和 `fzf-lua` 结果界面。

完成后的行为应满足：

1. 普通项目首次打开时在 Neovim 缓存目录后台建库，保存文件后增量更新。
2. 从当前文件向上找到项目内 `GTAGS` 时，手动数据库优先，禁止为同一项目再生成缓存数据库。
3. `.notags` 明确禁止自动索引；新的大型仓库先放置该标记，再由用户手动建立 `GTAGS`。
4. 查询始终只使用当前 buffer 对应的数据库，不混入其他项目结果。
5. 单个结果直接跳转，多个结果进入 `fzf-lua`，不打开内置 quickfix 窗口。
6. 不再依赖 `cscope_maps.nvim` 或 Neovim 已删除的原生 cscope 功能。

## 背景与兼容性结论

当前配置的 `lua/plugins/gtags.lua` 使用 `cscope_maps.nvim`、项目内 `GTAGS` 和 Telescope，索引由用户手动建立。这样适合 Linux 内核等超大项目，但普通项目无法获得文章中的自动后台维护体验。

本机环境：

- Neovim 0.12.3，`has('cscope') == 0`。
- GNU GLOBAL 6.6.12，`gtags`、`global`、`gtags-cscope` 均已安装。
- Universal Ctags 5.9.0、Pygments 2.11.2 已安装。
- `gtags.conf` 位于 GNU GLOBAL 的安装数据目录。

不能直接使用 `gutentags_plus` README 中的 `ludovicchabant/vim-gutentags`。其当前 HEAD 会因 Neovim 没有原生 cscope 而在加载 `gtags_cscope` 模块时抛错。依赖改用 `skywind3000/vim-gutentags`：该分支包含 Neovim 0.9+ 兼容补丁，与 `skywind3000/gutentags_plus` 配套。两者维护活跃度较低，最终版本必须写入 `lazy-lock.json`。

`gutentags_plus` 在 Neovim 0.9+ 不调用 `:cscope`，而是同步执行外部 `gtags-cscope` 并将结果写入 quickfix。因此移除 `cscope_maps.nvim` 后，查询能力仍然成立。设计阶段已经完成两条隔离验证：

- 仅加载 `gutentags_plus`，使用现有 Linux 内核手动数据库，定义查询正确定位到 `mm/vmscan.c:5962`。
- 仅加载兼容版 `vim-gutentags` 与 `gutentags_plus`，在临时缓存自动建立数据库后，定义查询返回 8 条有效结果。

两次验证中 `cscope_maps.nvim` 均未加载，Neovim 原生 cscope 均不可用。

## 方案选择

采用统一查询适配层：自动库与手动库都向 `gutentags_plus` 提供它需要的 buffer-local 项目根和数据库路径，统一调用 `GscopeFind!`。不保留双后端，也不重新实现 `gtags-cscope` 输出解析。

未采用的方案：

- 保留 `cscope_maps.nvim` 仅处理手动库：会产生两套数据库状态、环境变量和查询行为，增加多项目切换风险。
- 完全用 Lua 重写 `gutentags_plus`：偏离用户指定插件，且扩大本次维护范围。

## 目标结构

```text
lua/
  gtags_adapter.lua       # 混合模式判定、统一查询、结果分派、索引更新
  plugins/
    gtags.lua             # lazy.nvim 插件声明及 Gutentags 全局配置
README.md                 # 依赖、模式判定、键位、排错与使用说明
lazy-lock.json            # 锁定两个 Skywind 插件，移除 cscope_maps.nvim
```

### `lua/plugins/gtags.lua`

该文件继续作为插件边界，声明：

- `skywind3000/gutentags_plus`
- `skywind3000/vim-gutentags`
- 已有的 `ibhagwan/fzf-lua`

插件在启动阶段加载，确保 Gutentags 的 `BufReadPost` 自动命令可以处理第一个文件。所有 `g:gutentags_*` 变量必须在 Vimscript 插件载入前设置，因此放在 lazy.nvim 的 `init` 阶段。

配置原则：

- 当 `gtags`、`global`、`gtags-cscope` 均可执行时，设置 `g:gutentags_modules = { "gtags_cscope" }`；否则使用空模块列表并由适配层在查询时报告缺失命令，避免启动阶段反复触发失败任务。
- 不额外生成项目级 ctags。LSP、Aerial 和 Tagbar 已覆盖语义跳转、文件大纲和单文件 ctags 职责。
- 缓存根为 `vim.fn.stdpath("cache") .. "/gutentags"`。
- 在默认 `.git`、`.svn`、`.hg` 等根标记之外增加 `.root` 和 `.project`。
- 明确设置 `g:gutentags_background_update = 1`、`g:gutentags_generate_on_missing = 1`、`g:gutentags_generate_on_new = 1`、`g:gutentags_generate_on_write = 1`，使后台建库和更新行为不依赖插件默认值。
- `setup()` 在插件载入前定义全局 Vim 可调用的混合模式守卫，并将其函数名设置到 `g:gutentags_init_user_func`。这是 Gutentags 初始化模块和缓存路径之前唯一受支持的 veto 点；不能用另一个 `BufReadPost` 事后补救。如果配置中已有该 hook，新守卫先调用旧 hook，只有两者都允许时才进入自动模式。
- `g:gutentags_auto_add_gtags_cscope = 0`，避免任何原生 cscope 连接。
- `g:gutentags_plus_nomap = 1`，禁用插件默认键位。其 `GscopeAdd`、`GscopeKill` 和默认 `<leader>ck` 在 Neovim 0.12 不可用。
- 启用高级诊断命令，保留 `GutentagsToggleTrace` 排错入口。
- `GTAGSLABEL` 使用 `native-pygments`。仅在 `gtags` 可执行时通过 `gtags --config=datadir` 获取安装数据目录；找到可读的 `gtags.conf` 后才设置 `GTAGSCONF`，不写死 `/usr/local`，也不让探测失败中断启动。

### `lua/gtags_adapter.lua`

适配层只对外提供三个入口：

- `setup()`：注册自动索引守卫、手动数据库探测和键位。
- `find(kind)`：解析当前上下文、检查数据库状态、执行查询和分派结果。
- `update()`：更新当前项目的自动或手动数据库。

插件声明的 `init` 阶段调用 `setup()`，使 `g:gutentags_init_user_func` 守卫早于 Gutentags 第一次 `BufReadPost` 执行。守卫在手动模式下写入当前 buffer 的项目根和数据库路径并返回 false；在禁用模式下记录 `.notags` 所在根并返回 false；在自动模式下返回 true，让 Gutentags 继续初始化。适配层不负责生成自动数据库，也不解析 `gtags-cscope` 输出；这些职责分别属于 `vim-gutentags` 和 `gutentags_plus`。

## 模式判定

从当前文件所在目录逐级向上扫描。每一层按 `GTAGS`、`.notags`、项目根标记的顺序检查；第一个命中的目录决定模式，扫描立即停止。这样同一目录内手动数据库优先，同时不会越过最近的嵌套项目边界误用父项目数据库。

判定结果为：

1. 当前层找到 `GTAGS`：手动模式。其所在目录就是项目根和数据库目录。自动索引守卫返回 false，避免 Gutentags 为同一项目建立缓存副本。
2. 当前层没有 `GTAGS`，但找到 `.notags`：禁用模式。Gutentags 不建库，查询时提示用户在该目录手动生成数据库。
3. 当前层没有上述文件，但找到 `.git`、`.root`、`.project` 等项目根标记：自动模式，具体根信息由 Gutentags 提供。
4. 没有任何项目标记：未配置模式。查询时提示在项目根创建 `.root`。

手动模式将以下值写入当前 buffer：

```text
b:gutentags_root = <GTAGS 所在目录>
b:gutentags_files.gtags_cscope = <GTAGS 绝对路径>
```

这正是 `gutentags_plus` 查询所需的接口。自动模式下，这两个值由 Gutentags 设置。状态保持 buffer-local；每次查询仍重新确认当前文件和数据库，避免切换项目后使用陈旧上下文。

## 查询数据流

用户按下查询键后：

1. `find(kind)` 获取光标下的 `<cword>`；文件和 include 查询改用 `<cfile>`。
2. 重新解析当前模式并准备 buffer-local 数据库上下文。
3. 检查查询所需的 `global` 和 `gtags-cscope` 是否可执行。`gtags-cscope` 会从 PATH 调用 `global`，所以两者缺一不可；`gtags` 只在自动生成或更新数据库时检查。
4. 自动模式下，如果 `gutentags#inprogress()` 包含 `gtags_cscope`，停止本次查询并提示状态。该 API 只公开模块级全局状态，无法区分项目，因此即使任务属于另一个自动项目也会保守地阻止查询。手动模式只在当前项目根已有 `global -u` 任务时阻止查询。不能仅凭 `GTAGS` 文件存在判断完成：实测表明文件会在首次建库结束前出现，过早查询会得到 `corrupted`。
5. 使用 `vim.api.nvim_cmd()` 结构化调用 `GscopeFind! {kind} {query}`。bang 阻止插件打开 quickfix 窗口，也避免自行拼接和转义 Ex 命令字符串。
6. 读取 quickfix，忽略 `gutentags_plus` 写入的标题项，只保留具有有效文件和行号的结果。
7. 零条结果显示通知；单条结果直接跳转；多条结果调用 `fzf-lua.quickfix({ valid_only = true })`。

查询是同步外部进程，完成后 quickfix 已可读取。`fzf-lua` 继续继承当前配置中的隐藏预览、`Ctrl-o` 切换预览和导航键。

## 键位

保留当前 `<leader>g*` 语义，不采用插件默认 `<leader>c*`：

| 键位 | Gscope 类型 | 行为 |
|---|---:|---|
| `<leader>gd` | `g` | 查定义 |
| `<leader>gs` | `s` | 查符号和引用 |
| `<leader>gr` | `c` | 查调用当前函数的位置 |
| `<leader>gt` | `t` | 查文本 |
| `<leader>ge` | `e` | egrep 查询 |
| `<leader>gf` | `f` | 查文件 |
| `<leader>gi` | `i` | 查 include 当前文件的位置 |
| `<leader>gb` | - | 更新当前项目索引 |

不映射 `d` 类型，因为 GNU `gtags-cscope` 不提供可靠的“当前函数调用了哪些函数”查询；不映射 `z` 类型，因为本设计不启用项目级 ctags 模块。

## 索引更新

`update()` 根据当前模式分派：

- 自动模式：执行当前 buffer 的 `GutentagsUpdate`。Gutentags 负责后台任务排队、保存时增量更新和完成事件。
- 手动模式：使用 `vim.system()` 在项目根异步执行 `global -u`，并设置当前项目的 `GTAGSROOT`、`GTAGSDBPATH`。适配层按项目根记录任务，防止重复启动，并在退出回调中报告结果。
- 禁用模式且没有 `GTAGS`：不自动执行全量建库，只提示用户先在项目根运行适合该项目的命令，例如普通项目使用 `gtags`，Linux 内核使用 `make gtags`。

适配层不会自动删除或覆盖手动数据库。数据库损坏时，README 给出自动缓存库与手动项目库各自的恢复步骤。

## 错误处理

- 缺少外部命令：不使 Neovim 启动失败；查询检查 `global` 与 `gtags-cscope`，自动更新检查 `gtags`，手动更新检查 `global`，并按当前动作列出缺失命令。
- 找不到项目根：提示创建 `.root`，不在当前工作目录盲目建库。
- `.notags` 且无 `GTAGS`：说明自动索引已关闭，并显示标记所在目录。
- 索引正在运行：提示等待完成，不查询半成品数据库。
- 无查询结果：显示查询词和类型，不打开空的 fzf 窗口。
- `gtags-cscope` 错误或数据库损坏：如果插件写入了非标题、无有效行号的错误条目，则显示该文本和数据库路径；否则显示通用查询失败、数据库路径，并提示查看 `:messages`。不承诺捕获插件仅通过 `echo` 输出的原始错误。
- 手动更新失败：在 `vim.schedule()` 回调中显示退出码和 stderr；成功时通知更新完成。
- 非普通 buffer、空文件名或已删除文件：不探测、不建库、不查询。

## 验证计划

本次改动跨越插件加载顺序、异步索引和外部查询，验证覆盖以下层次：

1. 适配层逻辑：验证手动 `GTAGS` 优先、`.notags` 禁用、无根提示，以及自动模式读取 Gutentags buffer 变量。
2. 查询结果分派：验证零条、单条和多条结果分别触发通知、直接跳转和 `fzf-lua`；标题项与损坏数据库错误不会被当作正常位置。
3. 自动集成：在临时小型 C 项目和隔离缓存中完成首次建库，等待 Gutentags 任务结束后查询已知定义，再触发一次更新。
4. 手动集成：使用现有 Linux 内核 `GTAGS` 查询已知符号，确认不创建缓存副本，并验证 `global -u` 的任务保护。
5. 禁用路径：在带 `.notags` 且无数据库的临时项目中确认不会启动 Gutentags 任务。
6. 完整配置：执行 headless 启动和 lazy.nvim 同步，确认无 Lua/Vimscript 加载错误；检查 `GscopeFind`、`GutentagsUpdate` 和自定义键位存在。
7. 依赖清理：确认运行时与 `lazy-lock.json` 不再包含 `cscope_maps.nvim`，两个 Skywind 插件被锁定。
8. 文档与工作树：确认 README 与实现一致，且用户现有的 `fzf-lua.lua`、`markdown.lua`、`markdown-preview.css`、`nvim.log` 改动未被覆盖或纳入无关提交。

## README 更新

README 的“大型代码库符号跳转”章节改为说明：

- 三个组件各自负责什么。
- 系统依赖和 `native-pygments` 条件。
- 自动、手动、`.notags` 三种状态及优先级。
- 缓存位置、项目根标记和首次建库行为。
- `<leader>g*` 键位以及零/单/多结果交互。
- `GutentagsToggleTrace`、数据库未就绪和损坏数据库的排错方法。
- 为什么使用 Skywind 的兼容分支，以及为什么不再使用 `cscope_maps.nvim`。

## 不做的事

- 不重新实现 Gutentags 的后台任务管理。
- 不 fork 或 vendor 两个 Vimscript 插件；依赖通过 lockfile 固定。
- 不恢复 Neovim 原生 cscope，也不提供 `GscopeAdd`、`GscopeKill`、`:Cscope`。
- 不同时维护 `cscope_maps.nvim` 与 `gutentags_plus` 两套查询后端。
- 不启用项目级 ctags 数据库，不增加 `GscopeFind z`。
- 不自动判断仓库规模；大型仓库由现有 `GTAGS` 或 `.notags` 明确识别。
- 不自动删除项目内手动数据库。
- 不改动与本功能无关的 LSP、Telescope、fzf-lua、Markdown 或 UI 配置。
