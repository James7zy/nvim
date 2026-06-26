return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    -- C 实现的排序器：超大结果集（内核级仓库）下输入过滤不再卡。
    -- 需要本机有 make + C 编译器，lazy 会自动 build。
    { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
  },
  config = function()
    local is_ok, telescope = pcall(require, "telescope")
    if not is_ok then
      return
    end
    local builtin = require("telescope.builtin")

    local actions_layout = require("telescope.actions.layout")

    telescope.setup({
      defaults = {
        -- 输入框在下方时用 ascending：最佳匹配排在最底部、紧挨输入框，符合直觉
        -- （类似 fzf/LeaderF 从下往上）。scroll limit 减少大结果集滚动卡顿。
        sorting_strategy = "ascending",
        scroll_strategy = "limit",

        -- ── 渲染减负（让 telescope 接近 LeaderF 的轻快，树莓派弱 CPU 尤其受益）──
        -- 关图标：telescope 每行结果都算 devicons + 相对路径，这是渲染开销大头
        disable_devicons = true,
        -- 更紧凑的布局，减少需要绘制的区域
        layout_strategy = "flex",
        layout_config = {
          height = 0.5,
          width = 0.9,
          prompt_position = "bottom", -- 输入框放窗口下方，结果列表在其上方
        },

        -- <C-y>：在搜索窗内随时开/关预览（grep 类默认隐藏预览以省渲染，
        -- 需要看上下文时按它调出来）。选 <C-y> 是因为 telescope 默认未占用它，
        -- 而 <C-p> 默认是“上移选择”，会冲突。insert/normal 两种模式都绑。
        mappings = {
          i = { ["<C-y>"] = actions_layout.toggle_preview },
          n = { ["<C-y>"] = actions_layout.toggle_preview },
        },

        -- 默认忽略构建产物 / 二进制 / 巨大目录（内核类仓库尤其重要）
        file_ignore_patterns = {
          "%.o$", "%.a$", "%.ko$", "%.mod%.c$", "%.cmd$",
          "%.bin$", "%.elf$", "%.img$", "%.dtb$",
          "^build/", "^out/", "%.git/",
        },
      },
      extensions = {
        fzf = {
          fuzzy = true,
          override_generic_sorter = true,
          override_file_sorter = true,
          case_mode = "smart_case",
        },
      },
    })

    -- 加载 fzf-native 扩展（装不上时静默跳过，不影响其它功能）
    pcall(telescope.load_extension, "fzf")

    -- find_files 默认探测命令名 "fd"，但 Ubuntu/Debian 把 fd 装成 "fdfind"
    -- （与同名旧包冲突）。这里自适应：优先 fd（多数发行版），其次 fdfind
    -- （Ubuntu/Debian），都没有则不指定、让 telescope 回退到 find。
    local fd_bin = vim.fn.executable("fd") == 1 and "fd"
      or (vim.fn.executable("fdfind") == 1 and "fdfind" or nil)
    local find_files_opts = fd_bin
      and { find_command = { fd_bin, "--type", "f", "--hidden", "--exclude", ".git" } }
      or {}

    -- 公共减负选项：预览默认隐藏（预览要读文件 + treesitter 高亮，树莓派上是
    -- 渲染卡顿的最大单项来源），但预览器仍然存在 ——
    -- 在搜索窗内按 <C-y> 可随时把预览调出来/收起来（toggle_preview）。
    --
    -- 关键：telescope 的 previewer = false 不是真删预览器，而是转成
    -- “保留默认预览器 + 启动时隐藏”（见 pickers.lua:1556 __hide_previewer），
    -- 正好让 toggle_preview 能把它恢复出来。之前用 preview_cutoff 把预览窗
    -- 彻底关掉反而导致 toggle 无效（layout.lua:35 走 else return）。
    local no_preview = {
      previewer = false,
    }

    vim.keymap.set("n", "<leader>ff", function()
      builtin.find_files(vim.tbl_extend("force", no_preview, find_files_opts))
    end, {})
    vim.keymap.set("n", "<leader>ft", builtin.git_files, {})
    vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
    vim.keymap.set("n", "<leader>fg", function() -- NOTE: requires ripgrep
      builtin.live_grep(no_preview)
    end)
    vim.keymap.set("n", "<leader>fc", function() -- fc = find by content
      builtin.grep_string(vim.tbl_extend("force", no_preview, {
        search = vim.fn.input("rg > "),
      }))
    end)

    -- grep_string 在内核级仓库里常命中上万行，让 ripgrep 自身做轻量过滤，
    -- 减少传给 telescope 渲染/排序的行数，是滚动卡顿的主要解法之一。
    local grep_args = {
      "--max-columns=200", -- 跳过超长行（压缩文件/生成代码），避免渲染巨行
      "--max-filesize=1M", -- 不去搜超大文件
      -- 兜底排除：内核树里 GTAGS/GRTAGS（>1.3G 二进制标签库）和编译产物会让
      -- ripgrep 硬读几 G 数据 → frb 慢到几十秒。理想情况靠仓库根的 .ignore，
      -- 这里再加一层 glob 防护，换到没放 .ignore 的仓库也安全。
      "--glob=!GTAGS", "--glob=!GRTAGS", "--glob=!GPATH", "--glob=!GSYMS",
      "--glob=!*.o", "--glob=!*.cmd", "--glob=!*.ko", "--glob=!*.a",
      "--glob=!vmlinux*", "--glob=!*.bin", "--glob=!*.elf", "--glob=!*.dtb",
    }

    -- 搜索当前光标的单词，精确匹配
    vim.keymap.set("n", "<leader>frb", function()
      builtin.grep_string(vim.tbl_extend("force", no_preview, {
        search = vim.fn.expand("<cword>"),
        word_match = "-w",
        additional_args = grep_args,
      }))
    end)

    -- 搜索当前光标的单词，模糊匹配
    vim.keymap.set("n", "<leader>frc", function()
      builtin.grep_string(vim.tbl_extend("force", no_preview, {
        search = vim.fn.expand("<cword>"),
        use_regex = true,
        additional_args = grep_args,
      }))
    end)
  end,
}
