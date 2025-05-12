vim.opt.termguicolors = true
require("bufferline").setup {
    options = {
        -- 左侧让出 nvim-tree 的位置
        offsets = {{
            filetype = "NvimTree",
            text = "File Explorer",
            highlight = "Directory",
            text_align = "left"
        }},
	mode = "buffers", -- 使用 buffer 模式，也支持 "tabs"
        numbers = "ordinal", -- 显示序号，方便快捷键跳转
        close_command = "bdelete! %d",       -- 关闭缓冲区
        right_mouse_command = "bdelete! %d",
        left_mouse_command = "buffer %d",    -- 左键点击切换
        middle_mouse_command = nil,
        indicator = {
          icon = '▎', style = 'icon',
        },
        buffer_close_icon = '',
        modified_icon = '●',
        close_icon = '',
        left_trunc_marker = '',
        right_trunc_marker = '',
        diagnostics = "nvim_lsp", -- 显示 LSP 诊断
        separator_style = "slant", -- 分隔符样式: "slant" | "thick" | "thin"
        show_buffer_close_icons = true,
        show_close_icon = true,
        enforce_regular_tabs = false,
        always_show_bufferline = true,
        sort_by = 'insert_after_current',
    }
}

-- 快捷键配置
local map = vim.keymap.set
map("n", "<Tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "下一个标签" })
map("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "上一个标签" })

-- 跳转到具体 buffer
for i = 1, 9 do
  map("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<CR>", { desc = "跳转到标签 " .. i })
end
