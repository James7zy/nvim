return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  config = function()
    local is_ok, builtin = pcall(require, "telescope.builtin")
    if not is_ok then
      return
    end

    -- find_files 默认探测命令名 "fd"，但 Ubuntu/Debian 把 fd 装成 "fdfind"
    -- （与同名旧包冲突）。这里自适应：优先 fd（多数发行版），其次 fdfind
    -- （Ubuntu/Debian），都没有则不指定、让 telescope 回退到 find。
    local fd_bin = vim.fn.executable("fd") == 1 and "fd"
      or (vim.fn.executable("fdfind") == 1 and "fdfind" or nil)
    local find_files_opts = fd_bin
      and { find_command = { fd_bin, "--type", "f", "--hidden", "--exclude", ".git" } }
      or {}

    vim.keymap.set("n", "<leader>ff", function()
      builtin.find_files(find_files_opts)
    end, {})
    vim.keymap.set("n", "<leader>ft", builtin.git_files, {})
    vim.keymap.set("n", "<leader>fb", builtin.buffers, {})
    vim.keymap.set("n", "<leader>fg", builtin.live_grep, {}) -- NOTE: requires ripgrep
    vim.keymap.set("n", "<leader>fc", function() -- fc = find by content
      builtin.grep_string({ search = vim.fn.input("rg > ") })
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
  end,
}
