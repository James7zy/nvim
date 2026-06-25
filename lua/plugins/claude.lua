return {
  "coder/claudecode.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    -- Server Configuration
    port_range = { min = 10000, max = 65535 },
    auto_start = true,
    log_level = "info", -- "trace", "debug", "info", "warn", "error"
    terminal_cmd = nil, -- Custom terminal command (default: "claude")
    -- For local installations: "~/.claude/local/claude"
    -- For native binary: use output from 'which claude'

    -- Send/Focus Behavior
    -- When true, successful sends focus the in-editor Claude terminal if already
    -- connected. NOTE: this only works for in-editor providers (snacks/native);
    -- it has no effect with provider = "none"/"external" (Claude runs outside
    -- Neovim). For those, hook the `User ClaudeCodeSendComplete` event.
    focus_after_send = false,

    -- Selection Tracking
    track_selection = true,
    visual_demotion_delay_ms = 50,

    -- Terminal Configuration
    terminal = {
      split_side = "right", -- "left" or "right"
      split_width_percentage = 0.60,
      -- Optional: shrink (or widen) the terminal while a diff is open. Defaults to
      -- split_width_percentage when unset, preserving today's behavior.
      diff_split_width_percentage = nil, -- e.g. 0.20 to give diffs more room
      provider = "auto", -- "auto", "snacks", "native", "external", "none", or custom provider table
      auto_close = true,
      snacks_win_opts = {}, -- Opts to pass to `Snacks.terminal.open()`
      -- Work around a Neovim core bug (< 0.12.2) that fragments large pastes into
      -- the terminal, making Cmd+V appear to truncate. true | false | "auto"
      -- ("auto", the default, enables it only on affected Neovim versions).
      fix_streamed_paste = "auto",

      -- Provider-specific options
      provider_opts = {
        -- Command for external terminal provider. Can be:
        -- 1. String with %s placeholder: "alacritty -e %s"
        -- 2. String with two %s placeholders: "alacritty --working-directory %s -e %s" (cwd, command)
        -- 3. Function returning command: function(cmd, env) return "alacritty -e " .. cmd end
        external_terminal_cmd = nil,
      },
    },

    -- Diff Integration
    diff_opts = {
      layout = "horizontal", -- "vertical" or "horizontal"
      open_in_new_tab = false,
      keep_terminal_focus = true, -- Keep focus in the Claude terminal when a diff opens (less intrusive)
      hide_terminal_in_new_tab = false,
      auto_resize_terminal = true, -- Let the plugin manage the terminal width across the diff lifecycle
      -- on_new_file_reject = "keep_empty", -- "keep_empty" or "close_window"

      -- Legacy aliases (still supported):
      -- vertical_split = true,
      -- open_in_current_tab = true,
    },
  },
  cmd = {
    "ClaudeCode",
    "ClaudeCodeFocus",
    "ClaudeCodeSelectModel",
    "ClaudeCodeAdd",
    "ClaudeCodeSend",
    "ClaudeCodeTreeAdd",
    "ClaudeCodeStatus",
    "ClaudeCodeStart",
    "ClaudeCodeStop",
    "ClaudeCodeOpen",
    "ClaudeCodeClose",
    "ClaudeCodeDiffAccept",
    "ClaudeCodeDiffDeny",
    "ClaudeCodeCloseAllDiffs",
  },
  keys = {
    { "<leader>a", nil, desc = "AI/Claude Code" },
    { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Toggle Claude" },
    { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Focus Claude" },
    { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Resume Claude" },
    { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Continue Claude" },
    { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Select Claude model" },
    { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Add current buffer" },
    { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude" },
    { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Accept diff" },
    { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Deny diff" },
  },
}
