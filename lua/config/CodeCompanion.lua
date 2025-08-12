
require("codecompanion").setup({
	adapters = {
		opts = {
			-- show_defaults 会导致copilot不能正常工作
			show_defaults = false,
			--log_level = "DEBUG",
		},

		deepseek = function()
			return require("codecompanion.adapters").extend("deepseek", {
				name = "deepseek",
				env = {
					api_key = function()
					  return os.getenv("DEEPSEEK_API_KEY")
					end,
				},

				schema = {
					model_opts = {
						default = "deepseek-coder",
						choices = {
							["deepseek-coder"] = { opts = { can_reason = true } },
							["deepseek-coder-2"] = { opts = { can_reason = true } },
							["deepseek-coder-3"] = { opts = { can_reason = true } },
							["deepseek-coder-4"] = { opts = { can_reason = true } },
						},
					},
					tool = {},
				},
			})
		end,

		siliconflow_v3 = function()
			return require("codecompanion.adapters").extend("deepseek", {
				name = "siliconflow_v3",
				url = "https://api.siliconflow.cn/v1/chat/completions",
				env = {
					api_key = function()
					  return os.getenv("DEEPSEEK_API_KEY_S")
					end,
				},
				schema = {
					model_opts = {
							default = "deepseek-ai/DeepSeek-V3",
							choices = {
							  ["deepseek-ai/DeepSeek-V3"] = { opts = { can_reason = true } },
							  ["deepseek-ai/DeepSeek-R1"] = { opts = { can_reason = true } },
							},
					},
				},
			})
		end,

		aliyun_deepseek = function()
			return require("codecompanion.adapters").extend("deepseek", {
				name = "aliyun_deepseek",
				url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
				env = {
					api_key = function()
						return os.getenv("DEEPSEEK_API_ALIYUN")
					end,
				},
				schema = {
					model_opts = {
						default = "deepseek-r1",
						choices = {
						  ["deepseek-r1"] = { opts = { can_reason = true } },
						},
					},
				},
			})
		end,

		-- 阿里千问
		-- https://help.aliyun.com/zh/model-studio/getting-started/models?spm=a2c4g.11186623.0.0.ce3c4823l7PTRL#9f8890ce29g5u
		aliyun_qwen = function()
			return require("codecompanion.adapters").extend("openai_compatible", {
				name = "aliyun_qwen",
				env = {
					url = "https://dashscope.aliyuncs.com",
					api_key = function()
						return os.getenv("DEEPSEEK_API_ALIYUN")
					end,
					chat_url = "/compatible-mode/v1/chat/completions",
				},
				schema = {
					model_opts = {
						default = "qwen-coder-plus-latest",
					},
				},
			})
		end,

		copilot_claude = function()
			return require("codecompanion.adapters").extend("copilot", {
				name = "copilot_claude",
				model_opts = {
				  model = {
				    default = "claude-3.7-sonnet",
				  },
				},
			})
		end,
		-- 禁用 openai fallback
		openai = function()
			return nil
		end,
	},

	strategies = {
		chat = { adapter = "deepseek" },
		inline = { adapter = "deepseek" },
	},

	opts = {
		language = "Chinese",
	},
	-------------------------------------------
--	prompt_library = {
--		["DeepSeek Explain"] = require("insis.ai.codecompanion.prompts.deepseek-explain"),
--		["Nextjs Agant"] = require("insis.ai.codecompanion.prompts.nextjs-agant"),
--	},		

})


