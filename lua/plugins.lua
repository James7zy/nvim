local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	--colortheme
	{
		"rebelot/kanagawa.nvim",
		config = function()
			vim.cmd("colorscheme kanagawa")
		end,
	},

	-- Vscode-like pictograms
	{
		"onsails/lspkind.nvim",
		event = { "VimEnter" },
	},

	-- Auto-completion engine
	{
		"hrsh7th/nvim-cmp",
		dependencies = {
			"lspkind.nvim",
			"hrsh7th/cmp-nvim-lsp", -- lsp auto-completion
			"hrsh7th/cmp-buffer", -- buffer auto-completion
			"hrsh7th/cmp-path", -- path auto-completion
			"hrsh7th/cmp-cmdline", -- cmdline auto-completion
		},
		config = function()
			require("config.nvim-cmp")
		end,
	},

	-- Code snippet engine
	{
		"L3MON4D3/LuaSnip",
		version = "v2.*",
	},

	-- LSP manager
	{
		"williamboman/mason.nvim",
		"williamboman/mason-lspconfig.nvim",
		"neovim/nvim-lspconfig",
	},

	-- File explorer nvim tree
	{
		"nvim-tree/nvim-tree.lua",
		dependencies = {
			"nvim-tree/nvim-web-devicons", -- optional, for file icons
		},
		config = function()
			require("config.nvim-tree")
		end,
	},

	-- easymotion find 
	{
		'easymotion/vim-easymotion',
		config = function()
			require("config.easymotion")
		end,
	},

	-- Treesitter-integration
	{
		"nvim-treesitter/nvim-treesitter",
		build = ":TSUpdate",
		config = function()
			require("config.nvim-treesitter")
		end,
	},

	-- Nvim-treesitter text objects
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		dependencies = "nvim-treesitter/nvim-treesitter",
		config = function()
			require("config.nvim-treesitter-textobjects")
		end,
	},

	-- aerial
	{
		"stevearc/aerial.nvim",
		opts = {
		},
		dependencies = { "nvim-treesitter/nvim-treesitter", "neovim/nvim-lspconfig" },
		config = function()
			require("config.aerial")
		end,
	 },

	-- tagbar 
	{
		"preservim/tagbar",
		config = function()
			require("config.tagbar")
		end,
	},

	-- Fuzzy finder
	{
		"nvim-telescope/telescope.nvim",
		--branch = "0.1.x",
		dependencies = {
			"nvim-lua/plenary.nvim" ,
			"nvim-treesitter/nvim-treesitter"
		},
		config = function()
			require("config.telescope")
		end,
	},

	-- Improve the performance of big file
	{
		"pteroctopus/faster.nvim",
	},

	-- A pretty list for showing diagnostics, references, telescope results, quickfix and location lists
	{
		"folke/trouble.nvim",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		keys = {
			{
				"<leader>xx",
				"<cmd>Trouble diagnostics toggle<cr>",
				desc = "Diagnostics (Trouble)",
			},
			{
				"<leader>xX",
				"<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
				desc = "Buffer Diagnostics (Trouble)",
			},
			{
				"<leader>cs",
				"<cmd>Trouble symbols toggle focus=false<cr>",
				desc = "Symbols (Trouble)",
			},
			{
				"<leader>cl",
				"<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
				desc = "LSP Definitions / references / ... (Trouble)",
			},
			{
				"<leader>xL",
				"<cmd>Trouble loclist toggle<cr>",
				desc = "Location List (Trouble)",
			},
			{
				"<leader>xQ",
				"<cmd>Trouble qflist toggle<cr>",
				desc = "Quickfix List (Trouble)",
			},
		},
		opts = function()
			require("config.trouble")
		end,
	},

	-- Highlighter
	{
		"azabiong/vim-highlighter",
		config = function()
			require("config.vim-highlighter")
		end,
	},

	--bufferline
	{
		'akinsho/bufferline.nvim',
		version = "*",
		dependencies = {
			'nvim-tree/nvim-web-devicons'
		},
		config = function()
			require("config.bufferline")
		end,
	},

	-- claude
	{
		"greggh/claude-code.nvim",
		dependencies = {
		  "nvim-lua/plenary.nvim", -- Required for git operations
		},
		config = function()
			require("config.claude")
		end,
	},

	-- Markdown
	{
               "tpope/vim-markdown",
               config = function()
                 -- tpope/vim-markdown
                 vim.g.markdown_syntax_conceal = 0
                 vim.g.markdown_fenced_languages =
                 { "html", "python", "bash=sh", "json", "java", "js=javascript", "sql", "yaml", "xml", 
                   "swift", "javascript", 'lua' }
               end,
       }, --> syntax highlighting and filetype plugins for Markdown

	{
		"iamcco/markdown-preview.nvim",
		cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
		build = "cd app && npm install",
		init = function()
		  vim.g.mkdp_filetypes = { "markdown" }
		  require("config.MarkdownPreview")
		end,
		ft = { "markdown" },
	},

	{
	  "rust-lang/rust.vim",
	  ft = { "rust", "markdown" },   -- 在 Rust 和 Markdown 文件中加载
	},

	{
		"j-hui/fidget.nvim",
		opts = {
		  -- options
		},
	}
})
