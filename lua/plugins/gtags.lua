-- ============================================================
-- GNU GLOBAL (gtags) 大型代码库索引 / 符号跳转
--   cscope_maps：用 gtags 的 cscope 接口做跳转，结果走 telescope
-- 前置：系统需安装 global -> `sudo apt install global` (提供 gtags/global)
-- 建索引：内核源码用自带 target `make gtags`；普通工程在根目录 `gtags`。
--         建好后目录里会有 GTAGS/GRTAGS/GPATH 三个文件。
--
-- 注意: 这里【不用 vim-gutentags】自动维护索引。原因——gutentags 的 cscope_maps
--       桥接会把 db 路径劫持到 ~/.cache/gutentags 下一个它自己生成的文件，若它没
--       生成成功(内核太大/被中断)，cscope_maps 就会去查一个不存在的库 -> 永远空结果，
--       而你手动建在源码树里的 GTAGS 反而没被使用。索引改动后按 <leader>gb 手动重建。
-- ============================================================
return {
  {
    "dhananjaylatkar/cscope_maps.nvim",
    dependencies = {
      "nvim-telescope/telescope.nvim",
    },
    event = "VeryLazy",
    opts = {
      disable_maps = true, -- 自己定义 keymap，避免覆盖默认
      -- 这些字段必须放在 cscope 子表里 —— cscope_maps.setup 只把 opts.cscope
      -- 转交给内层 cscope 模块，放顶层会被忽略(仍用默认 cscope/cscope.out)。
      cscope = {
        exec = "gtags-cscope",          -- 用 GNU GLOBAL 后端而非默认 cscope
        db_file = "GTAGS",              -- 直接用源码树里的 GTAGS(默认是 ./cscope.out)
        picker = "telescope",           -- 结果走 telescope
        skip_picker_for_single_result = true,
        db_build_cmd = { script = "gtags", args = {} },
      },
    },
    config = function(_, opts)
      require("cscope_maps").setup(opts)

      -- cscope_maps 用相对路径 "GTAGS" + get_rel_path(getcwd(),..) 定位库，且查询前
      -- 对该路径做 fs_stat —— 只有 cwd 是 GTAGS 所在目录时 stat 才成功，否则静默返回空。
      -- 解决: 打开文件时向上找到 GTAGS, 把 cwd 切到它所在目录(同时设 GTAGSROOT 双保险)。
      vim.api.nvim_create_autocmd({ "BufEnter" }, {
        callback = function(args)
          local name = vim.api.nvim_buf_get_name(args.buf)
          if name == "" or vim.bo[args.buf].buftype ~= "" then return end
          local found = vim.fs.find("GTAGS", { upward = true, path = vim.fs.dirname(name) })[1]
          if not found then return end
          local root = vim.fs.dirname(found)
          vim.env.GTAGSROOT = root
          vim.env.GTAGSDBPATH = root
          if vim.fn.getcwd() ~= root then
            vim.cmd("cd " .. vim.fn.fnameescape(root))
          end
        end,
      })

      local map = function(lhs, sym, desc)
        vim.keymap.set("n", lhs, function()
          vim.cmd("Cscope find " .. sym .. " " .. vim.fn.expand("<cword>"))
        end, { silent = true, desc = desc })
      end

      -- g 系前缀（GNU GLOBAL）。光标停在符号上直接按。
      map("<leader>gd", "g", "Gtags: 跳到定义 (definition)")
      map("<leader>gr", "c", "Gtags: 找调用此函数的地方 (callers)")
      map("<leader>gs", "s", "Gtags: 找此符号的所有出现 (symbol/references)")
      map("<leader>gt", "t", "Gtags: 找此文本 (text)")
      map("<leader>ge", "e", "Gtags: egrep 模式查找")
      map("<leader>gf", "f", "Gtags: 打开此文件")
      map("<leader>gi", "i", "Gtags: 找 include 此文件的地方")

      -- 重建索引（首次进内核源码或大改动后手动跑一次最稳）
      vim.keymap.set("n", "<leader>gb", "<cmd>Cscope build<CR>",
        { silent = true, desc = "Gtags: 重建索引 (build)" })
    end,
  },
}
