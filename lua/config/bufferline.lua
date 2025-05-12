vim.opt.termguicolors = true
require("bufferline").setup {
    options = {
        -- left nvim-tree 
        offsets = {{
            filetype = "NvimTree",
            text = "File Explorer",
            highlight = "Directory",
            text_align = "left"
        }},
	mode = "buffers", -- buffer mode
        numbers = "ordinal", -- show num
        close_command = "bdelete! %d",       --close buffer 
        right_mouse_command = "bdelete! %d",
        left_mouse_command = "buffer %d",    -- click left to close
        middle_mouse_command = nil,
        indicator = {
          icon = '▎', style = 'icon',
        },
        buffer_close_icon = '',
        modified_icon = '●',
        close_icon = '',
        left_trunc_marker = '',
        right_trunc_marker = '',
        diagnostics = "nvim_lsp", 
        separator_style = "slant", -- "slant" | "thick" | "thin"
        show_buffer_close_icons = true,
        show_close_icon = true,
        enforce_regular_tabs = false,
        always_show_bufferline = true,
        sort_by = 'insert_after_current',
    }
}

--keymap 
local map = vim.keymap.set
map("n", "<Tab>", "<cmd>BufferLineCycleNext<CR>", { desc = "next buffer" })
map("n", "<S-Tab>", "<cmd>BufferLineCyclePrev<CR>", { desc = "before buffer" })

-- jump buffer
for i = 1, 9 do
  map("n", "<leader>" .. i, "<cmd>BufferLineGoToBuffer " .. i .. "<CR>", { desc = "jump buffer" .. i })
end
