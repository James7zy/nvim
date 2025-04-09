-- 设置 tagbar 子窗口出现在左边
vim.g.tagbar_left = 1

-- 设置标签子窗口的宽度
vim.g.tagbar_width = 32

-- 子窗口中不显示冗余帮助信息
vim.g.tagbar_compact = 1

-- 定义 cpp 的标签种类和作用域规则
vim.g.tagbar_type_cpp = {
  kinds = {
    "c:classes:0:1",
    "d:macros:0:1",
    "e:enumerators:0:0",
    "f:functions:0:1",
    "g:enumeration:0:1",
    "l:local:0:1",
    "m:members:0:1",
    "n:namespaces:0:1",
    "p:functions_prototypes:0:1",
    "s:structs:0:1",
    "t:typedefs:0:1",
    "u:unions:0:1",
    "v:global:0:1",
    "x:external:0:1"
  },
  sro = "::",
  kind2scope = {
    g = "enum",
    n = "namespace",
    c = "class",
    s = "struct",
    u = "union"
  },
  scope2kind = {
    enum = "g",
    namespace = "n",
    class = "c",
    struct = "s",
    union = "u"
  }
}

vim.keymap.set("n", "<leader>ilt", "<cmd>TagbarToggle<CR>", { desc = "Toggle Tagbar" })
