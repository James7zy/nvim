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
        -- 默认隐藏预览，保持轻快；需要时在窗内按 <C-y> 切换（见下方 keymap）
        preview = { hidden = "hidden" },
      },
      keymap = {
        fzf = {
          -- 在 fzf 窗口内按 ctrl-y 切换预览显示/隐藏，对标 telescope 的 <C-y>
          ["ctrl-y"] = "toggle-preview",
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
