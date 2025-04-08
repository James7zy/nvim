local is_ok, builtin = pcall(require, "telescope.builtin")
if not is_ok then
	return
end

vim.keymap.set("n", "<leader>ff", builtin.find_files, {})
vim.keymap.set("n", "<leader>fg", builtin.git_files, {})
vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
vim.keymap.set("n", "<leader>flg", builtin.live_grep, {}) -- NOTE: requires ripgrpe
vim.keymap.set(
	"n", "<leader>fc", function() -- fc = find by content
	builtin.grep_string({ search = vim.fn.input("Grep > ") })
end)

-- 搜索当前光标的单词，精确匹配
vim.keymap.set("n", "<leader>frb", function()
    local word = vim.fn.expand("<cword>")
    builtin.grep_string({ search = word, word_match = "-w" })
end)

-- 搜索当前光标的单词，模糊匹配
vim.keymap.set("n", "<leader>frc", function()
    local word = vim.fn.expand("<cword>")
    builtin.grep_string({ search = word, use_regex = true })
end)
