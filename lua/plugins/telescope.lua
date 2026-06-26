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

        -- <C-o>：在搜索窗内随时开/关预览（grep 类默认隐藏预览以省渲染，
        -- 需要看上下文时按它调出来）。与 fzf-lua 的切预览键保持一致（o=open）。
        -- insert/normal 两种模式都绑。
        mappings = {
          i = { ["<C-o>"] = actions_layout.toggle_preview },
          n = { ["<C-o>"] = actions_layout.toggle_preview },
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

    -- 加载 fzf-native 扩展（仍被 telescope 的其它入口/扩展用，如 aerial 浏览）
    pcall(telescope.load_extension, "fzf")

    -- 注意：<leader>f*（ff/ft/fb/fg/fc/frb/frc）这套搜索键已移交给 fzf-lua
    -- （见 lua/plugins/fzf-lua.lua）——fzf-lua 把搜索/排序外包给独立 fzf 进程，
    -- 在树莓派这类弱主机上更轻快。telescope 本体在此保留，因为 gtags 跳转
    -- （cscope_maps，gtags.lua）和 aerial 大纲（aerial.lua）仍以它作为 picker。
    -- 上面的 setup（disable_devicons / <C-o> 切预览 / file_ignore_patterns）
    -- 对这些保留的 telescope 入口依然生效。
    --
    -- ↓↓↓ 原 telescope 版的 <leader>f* 键位，暂时注释保留。若想从 fzf-lua 切回
    -- telescope：删掉/注释 fzf-lua.lua 里的同名 keymap，再取消下面整段注释即可。
    --
    -- local builtin = require("telescope.builtin")
    --
    -- -- find_files 默认探测命令名 "fd"，但 Ubuntu/Debian 把 fd 装成 "fdfind"。
    -- local fd_bin = vim.fn.executable("fd") == 1 and "fd"
    --   or (vim.fn.executable("fdfind") == 1 and "fdfind" or nil)
    -- local find_files_opts = fd_bin
    --   and { find_command = { fd_bin, "--type", "f", "--hidden", "--exclude", ".git" } }
    --   or {}
    --
    -- -- 公共减负选项：预览默认隐藏，<C-o> 可在窗内切换（见上方 setup 的 mappings）。
    -- local no_preview = { previewer = false }
    --
    -- vim.keymap.set("n", "<leader>ff", function()
    --   builtin.find_files(vim.tbl_extend("force", no_preview, find_files_opts))
    -- end, {})
    -- vim.keymap.set("n", "<leader>ft", builtin.git_files, {})
    -- vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
    -- vim.keymap.set("n", "<leader>fg", function() -- NOTE: requires ripgrep
    --   builtin.live_grep(no_preview)
    -- end)
    -- vim.keymap.set("n", "<leader>fc", function() -- fc = find by content
    --   builtin.grep_string(vim.tbl_extend("force", no_preview, {
    --     search = vim.fn.input("rg > "),
    --   }))
    -- end)
    --
    -- -- grep_string 让 ripgrep 自身做轻量过滤 + 兜底排除 GTAGS 等二进制。
    -- local grep_args = {
    --   "--max-columns=200",
    --   "--max-filesize=1M",
    --   "--glob=!GTAGS", "--glob=!GRTAGS", "--glob=!GPATH", "--glob=!GSYMS",
    --   "--glob=!*.o", "--glob=!*.cmd", "--glob=!*.ko", "--glob=!*.a",
    --   "--glob=!vmlinux*", "--glob=!*.bin", "--glob=!*.elf", "--glob=!*.dtb",
    -- }
    --
    -- -- 搜索当前光标的单词，精确匹配
    -- vim.keymap.set("n", "<leader>frb", function()
    --   builtin.grep_string(vim.tbl_extend("force", no_preview, {
    --     search = vim.fn.expand("<cword>"),
    --     word_match = "-w",
    --     additional_args = grep_args,
    --   }))
    -- end)
    --
    -- -- 搜索当前光标的单词，模糊匹配
    -- vim.keymap.set("n", "<leader>frc", function()
    --   builtin.grep_string(vim.tbl_extend("force", no_preview, {
    --     search = vim.fn.expand("<cword>"),
    --     use_regex = true,
    --     additional_args = grep_args,
    --   }))
    -- end)
  end,
}
