--Highlighter keymap
vim.cmd([[
	let HiSet   = 'f<CR>'
	let HiErase = 'f<BS>'
	let HiClear = 'f<C-L>'
	let HiFind  = 'f<Tab>'
	let HiSetSL = 't<CR>'

	" jump key mappings
	nn n <Cmd>call HiSearch('n')<CR>
	nn N <Cmd>call HiSearch('N')<CR>
	
	" :noh commmand mapping, if there isn't
	nn <Esc>n <Cmd>noh<CR>
]])

