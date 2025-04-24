vim.g.gutentags_trace = 1

-- 开启 gutentags 的高级调试命令
vim.g.gutentags_define_advanced_commands = 1

vim.g.gutentags_project_root = {
  '.git', 'compile_commands.json', 'Makefile', 'CMakeLists.txt'
}

vim.g.gutentags = {
  modules = { 'ctags', 'gtags_cscope' },
  global_executable = '/usr/bin/global', -- 通过 `which global` 确认路径
  file_list_command = 'rg --files',
  trace = true,
  async = false 
}

-- 可选：标签缓存目录配置
vim.g.gutentags_cache_dir = vim.fn.expand('~/.cache/nvim/tags/')
vim.fn.mkdir(vim.g.gutentags_cache_dir, 'p') -- 自动创建目录

-- 排除不需要生成标签的目录
vim.g.gutentags_ctags_exclude = {
  'node_modules', 'build/*', 'dist/*', '*.git', '*.svg', '*.png'
}

---- 生成的 tags 文件名
--vim.g.gutentags_ctags_tagfile = '.tags'
--

---- 设置 ctags 参数
--vim.g.gutentags_ctags_extra_args = {
--  '--fields=+niazS',
--  '--extra=+q',
--  '--c++-kinds=+px',
--  '--c-kinds=+px',
--  '--output-format=e-ctags',  -- 如果你用的是 Universal Ctags，建议开启
--}

---- 禁用自动添加 gtags 数据库的行为
--vim.g.gutentags_auto_add_gtags_cscope = 0

vim.cmd [[
  call add(g:gutentags_project_info,
    \ {'type': 'c', 'glob': '*.c'})
  call add(g:gutentags_project_info,
    \ {'type': 'cpp', 'glob': '*.cpp'})
]]
