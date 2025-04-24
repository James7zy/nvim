local keymap = vim.keymap.set
local opts = { noremap = true, silent = true, desc = "GscopeFind" }

-- 快捷键绑定映射
keymap('n', '<leader>gs', ':GscopeFind s <C-R><C-W><CR>', opts)
keymap('n', '<leader>gg', ':GscopeFind g <C-R><C-W><CR>', opts)
keymap('n', '<leader>gc', ':GscopeFind c <C-R><C-W><CR>', opts)
keymap('n', '<leader>gt', ':GscopeFind t <C-R><C-W><CR>', opts)
keymap('n', '<leader>ge', ':GscopeFind e <C-R><C-W><CR>', opts)
keymap('n', '<leader>gf', ':GscopeFind f <C-R>=expand("<cfile>")<CR><CR>', opts)
keymap('n', '<leader>gi', ':GscopeFind i <C-R>=expand("<cfile>")<CR><CR>', opts)
keymap('n', '<leader>gd', ':GscopeFind d <C-R><C-W><CR>', opts)
keymap('n', '<leader>ga', ':GscopeFind a <C-R><C-W><CR>', opts)
keymap('n', '<leader>gz', ':GscopeFind z <C-R><C-W><CR>', opts)
