return {
  {
    "skywind3000/gutentags_plus",
    dependencies = {
      "skywind3000/vim-gutentags",
      "ibhagwan/fzf-lua",
    },
    lazy = false,
    init = function()
      local required = { "gtags", "global", "gtags-cscope" }
      local ready = true
      for _, command in ipairs(required) do
        ready = ready and vim.fn.executable(command) == 1
      end

      vim.g.gutentags_modules = ready and { "gtags_cscope" } or {}
      vim.g.gutentags_add_default_project_roots = 1
      vim.g.gutentags_project_root = { ".root", ".project" }
      vim.g.gutentags_cache_dir = vim.fn.stdpath("cache") .. "/gutentags"
      vim.g.gutentags_background_update = 1
      vim.g.gutentags_generate_on_missing = 1
      vim.g.gutentags_generate_on_new = 1
      vim.g.gutentags_generate_on_write = 1
      vim.g.gutentags_auto_add_gtags_cscope = 0
      vim.g.gutentags_plus_nomap = 1
      vim.g.gutentags_plus_switch = 0
      vim.g.gutentags_define_advanced_commands = 1

      vim.env.GTAGSLABEL = "native-pygments"
      if vim.fn.executable("gtags") == 1 then
        local result = vim.system({ "gtags", "--config=datadir" }, { text = true }):wait()
        if result.code == 0 then
          local config = vim.trim(result.stdout or "") .. "/gtags/gtags.conf"
          if vim.fn.filereadable(config) == 1 then
            vim.env.GTAGSCONF = config
          end
        end
      end

      require("gtags_adapter").setup()
    end,
  },
}
