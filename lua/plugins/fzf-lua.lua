-- ============================================================
-- fzf-lua：把搜索/排序/渲染外包给独立的 fzf 进程，nvim 主线程不被阻塞。
-- 在弱主机（树莓派）+ 大仓库下通常比 telescope 更快更轻 —— 这是它接管
-- <leader>f* 键位的原因。telescope 本体保留（gtags 跳转 / aerial 还依赖它），
-- 只是把这些 keymap 让给 fzf-lua。
--
-- 前置：系统已装 fzf(>0.36) + rg + fd，均已满足。
-- ============================================================
return {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local ok, fzf = pcall(require, "fzf-lua")
    if not ok then
      return
    end

    fzf.setup({
      -- 窗口：输入框在下方（--layout=reverse 是 fzf 默认，prompt 在底、结果向上）
      fzf_opts = { ["--layout"] = "reverse" },
      winopts = {
        height = 0.85,
        width = 0.90,
        -- 默认隐藏预览，保持轻快；需要时在窗内按 Ctrl+o 切换（见下方 keymap）。
        -- hidden 是 boolean（见 win.lua 文档），用 true 而非字符串 "hidden"。
        preview = { hidden = true },
      },
      -- Tab 默认是 toggle+down：会标记当前项，Enter 优先打开被标记的第一项。
      -- 这里改成纯上下移动，避免 Tab 选中后 Enter 仍打开第一项。
      -- 其余键位用 fzf-lua 默认；只重绑切预览键：默认是 F4，但 F4 常被操作系统/终端截获按不出来，
      -- 改用不会被截获、语义直观（o=open/overview）的 Ctrl+o。
      --
      -- 关键：fzf-lua 用的是 builtin previewer（neovim 浮窗渲染预览），它的
      -- toggle-preview 动作注册在 keymap.builtin（neovim 层），而不是 keymap.fzf
      -- （fzf 二进制层）。键名要用 nvim 的 <C-o> termcode 格式，而非 fzf 的写法。
      keymap = {
        builtin = {
          ["<C-o>"] = "toggle-preview",
          -- 预览内容半页滚动（对标 vim 的 Ctrl+d/u）。默认预览翻页是 Shift+↓/↑，
          -- 这里补上更顺手的 Ctrl+d/u。注意必须用 builtin 表里的 preview-*
          -- 动作名（预览是 neovim builtin previewer 渲染的）。
          ["<C-d>"] = "preview-half-page-down",
          ["<C-u>"] = "preview-half-page-up",
        },
        fzf = {
          ["tab"] = "down",
          ["shift-tab"] = "up",
        },
      },
      grep = {
        -- 跟 telescope 的 grep_args 对齐：跳过超长行 + 不搜超大文件 + 排除
        -- GTAGS 等二进制（没放 .ignore 的仓库的兜底防护）。
        rg_opts = table.concat({
          "--column --line-number --no-heading --color=always --smart-case",
          "--max-columns=200 --max-filesize=1M",
          "-g '!GTAGS' -g '!GRTAGS' -g '!GPATH' -g '!GSYMS'",
          "-g '!*.o' -g '!*.cmd' -g '!*.ko' -g '!*.a'",
          "-g '!vmlinux*' -g '!*.bin' -g '!*.elf' -g '!*.dtb'",
          "-e",
        }, " "),
      },
    })

    -- ── 键位：接管原 telescope 的 <leader>f* 这套 ──
    local map = function(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { silent = true, desc = desc })
    end

    map("<leader>ff", fzf.files, "fzf: 找文件")
    map("<leader>ft", fzf.git_files, "fzf: git 跟踪的文件")
    map("<leader>fb", fzf.buffers, "fzf: 已打开的 buffer")
    map("<leader>fg", fzf.live_grep, "fzf: 实时全文搜索 (rg)")
    map("<leader>fc", fzf.grep, "fzf: 手输关键词搜索")

    -- frb：光标下单词，精确（词边界）。grep_cword + --word-regexp
    map("<leader>frb", function()
      fzf.grep_cword({ rg_opts =
        "--column --line-number --no-heading --color=always --smart-case "
        .. "--max-columns=200 --max-filesize=1M --word-regexp -e" })
    end, "fzf: 光标词精确搜索")

    -- frc：光标下单词，正则/模糊（不加词边界）
    map("<leader>frc", fzf.grep_cword, "fzf: 光标词模糊搜索")
  end,
}
