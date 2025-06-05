
require("codecompanion").setup({
	opts = {
		log_level = "DEBUG", -- or "TRACE"
		adapters = {
			openai = function()
				return require("codecompanion.adapters").extend("openai", {
				  env = {
				    api_key = "cmd:op read op://personal/OpenAI/credential --no-newline",
				  },
			})
			end,

			deepseek = function()
				 return require("codecompanion.adapters").extend("deepseek", {
				   env = {
				     api_key = "cmd:op read op://personal/DeepSeek_API/credential --no-newline",
				   },
				 })
				end,
		},
	}
})

