vim.g.gutentags_trace = 1

-- 设置工程目录标志
vim.g.gutentags_project_root = { '.root', '.svn', '.git', '.hg', '.project' }

-- 生成的 tags 文件名
vim.g.gutentags_ctags_tagfile = '.tags'

-- 初始化模块列表
vim.g.gutentags_modules = {}

-- 启用 ctags
if vim.fn.executable('ctags') == 1 then
  table.insert(vim.g.gutentags_modules, 'ctags')
end

-- 启用 gtags + gtags-cscope
if vim.fn.executable('gtags-cscope') == 1 and vim.fn.executable('gtags') == 1 then
  table.insert(vim.g.gutentags_modules, 'gtags_cscope')
end

-- 设置缓存目录，防止污染工程目录
vim.g.gutentags_cache_dir = vim.fn.expand('~/.cache/tags')

-- 设置 ctags 参数
vim.g.gutentags_ctags_extra_args = {
  '--fields=+niazS',
  '--extra=+q',
  '--c++-kinds=+px',
  '--c-kinds=+px',
  '--output-format=e-ctags',  -- 如果你用的是 Universal Ctags，建议开启
}

-- 禁用自动添加 gtags 数据库的行为
vim.g.gutentags_auto_add_gtags_cscope = 0
