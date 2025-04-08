-- lua/config/easymotion.lua

-- 设置快捷键映射，避免与正常键盘输入冲突
--
-- <Leader>f{char} 跳转到字符 {char}
vim.api.nvim_set_keymap('n', '<Leader>f', '<Plug>(easymotion-bd-f)', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>f', '<Plug>(easymotion-overwin-f)', { noremap = true, silent = true })

-- s{char}{char} 跳转到字符 {char}{char}
vim.api.nvim_set_keymap('n', 's', '<Plug>(easymotion-overwin-f2)', { noremap = true, silent = true })

-- 跳转到行
vim.api.nvim_set_keymap('n', '<Leader>L', '<Plug>(easymotion-bd-jk)', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>L', '<Plug>(easymotion-overwin-line)', { noremap = true, silent = true })

-- 跳转到单词
vim.api.nvim_set_keymap('n', '<Leader>w', '<Plug>(easymotion-bd-w)', { noremap = true, silent = true })
vim.api.nvim_set_keymap('n', '<Leader>w', '<Plug>(easymotion-overwin-w)', { noremap = true, silent = true })

