
vim.g.gutentags_modules = {"cscope_maps"}

vim.g.gutentags_cscope_build_inverted_index_maps = 1

vim.g.gutentags_trace = 1

vim.g.gutentags_define_advanced_commands = 1

vim.g.gutentags_project_root = {
  '.git', 'compile_commands.json', 'Makefile', 'CMakeLists.txt'
}

vim.g.gutentags = {
  modules = { 'ctags', 'gtags_cscope' },
  global_executable = '/usr/bin/global',
  file_list_command = 'rg --files',
  trace = true,
  async = false 
}

vim.g.gutentags_cache_dir = vim.fn.expand('~/.cache/nvim/tags/')

vim.g.gutentags_file_list_command = "fd -e c -e h"

vim.fn.mkdir(vim.g.gutentags_cache_dir, 'p')

vim.g.gutentags_ctags_exclude = {
  'node_modules', 'build/*', 'dist/*', '*.git', '*.svg', '*.png'
}

vim.cmd [[
  call add(g:gutentags_project_info,
    \ {'type': 'c', 'glob': '*.c'})
  call add(g:gutentags_project_info,
    \ {'type': 'cpp', 'glob': '*.cpp'})
]]
