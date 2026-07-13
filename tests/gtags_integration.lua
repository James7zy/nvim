if not vim.g.lazy_did_setup then
  -- Neovim's -l mode skips user initialization and disables plugin loading.
  vim.go.loadplugins = true
  dofile(vim.fn.stdpath("config") .. "/init.lua")
end

local temp_root = vim.fn.tempname()
local auto_cache_dir
local auto_buf
local manual_root
vim.fn.mkdir(temp_root, "p")

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines or {}, path) == 0)
end

local function make_newer(path, database)
  local database_mtime = assert(vim.uv.fs_stat(database)).mtime.sec
  local touched, touch_error = vim.uv.fs_utime(path, "omit", database_mtime + 1)
  assert(touched, touch_error)
  assert(assert(vim.uv.fs_stat(path)).mtime.sec > database_mtime,
    path .. " is not newer than " .. database)
end

local function edit(path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
end

local function cursor_on(word)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  local col = assert(line:find(word, 1, true), "word not found: " .. word) - 1
  vim.api.nvim_win_set_cursor(0, { row, col })
end

local function jobs(bufnr)
  local function inspect()
    local current = vim.fn["gutentags#inprogress"]()
    assert(type(current) == "table", "Gutentags returned invalid job state")
    return current
  end
  if bufnr ~= nil and not vim.api.nvim_buf_is_valid(bufnr) then
    return nil, "automatic buffer is no longer valid"
  end
  local ok, current
  if bufnr == nil then
    ok, current = pcall(inspect)
  else
    ok, current = pcall(vim.api.nvim_buf_call, bufnr, inspect)
  end
  if ok then
    return current, nil
  end
  return nil, tostring(current)
end

local function cache_entries()
  local entries = vim.fn.glob(vim.fn.stdpath("cache") .. "/gutentags/*", false, true)
  table.sort(entries)
  return entries
end

local function check_failed_datadir_discovery()
  local plugin = assert(dofile(vim.fn.stdpath("config") .. "/lua/plugins/gtags.lua"))[1]
  local init = assert(plugin and plugin.init)
  local original_system = vim.system
  local original_adapter = package.loaded.gtags_adapter
  local original_config = vim.env.GTAGSCONF
  local original_label = vim.env.GTAGSLABEL
  local global_names = {
    "gutentags_modules", "gutentags_add_default_project_roots",
    "gutentags_project_root", "gutentags_cache_dir",
    "gutentags_background_update", "gutentags_generate_on_missing",
    "gutentags_generate_on_new", "gutentags_generate_on_write",
    "gutentags_auto_add_gtags_cscope", "gutentags_plus_nomap",
    "gutentags_plus_switch", "gutentags_define_advanced_commands",
  }
  local original_globals = {}
  for _, name in ipairs(global_names) do
    original_globals[name] = vim.deepcopy(vim.g[name])
  end
  local failures = {}

  local function check(name, system, verify)
    local setup_calls = 0
    local sentinel = temp_root .. "/existing-gtags.conf"
    vim.system = system
    package.loaded.gtags_adapter = {
      setup = function() setup_calls = setup_calls + 1 end,
    }
    vim.env.GTAGSCONF = sentinel
    local ok, err = xpcall(function()
      local init_ok, init_error = pcall(init)
      assert(init_ok, init_error)
      assert(setup_calls == 1, "adapter setup did not run")
      assert(vim.env.GTAGSCONF == sentinel, "failed discovery changed GTAGSCONF")
      verify()
    end, debug.traceback)
    vim.system = original_system
    package.loaded.gtags_adapter = original_adapter
    vim.env.GTAGSCONF = original_config
    vim.env.GTAGSLABEL = original_label
    for _, global_name in ipairs(global_names) do
      vim.g[global_name] = original_globals[global_name]
    end
    if not ok then
      failures[#failures + 1] = name .. "\n" .. err
    end
  end

  local observed_command, observed_options, observed_timeout
  check("times out datadir discovery without breaking setup", function(command, options)
    observed_command = command
    observed_options = options
    return {
      wait = function(_, timeout)
        observed_timeout = timeout
        return nil
      end,
    }
  end, function()
    assert(vim.deep_equal({ "gtags", "--config=datadir" }, observed_command),
      "datadir discovery used the wrong command")
    assert(type(observed_options) == "table" and observed_options.text == true,
      "datadir discovery did not request text output")
    assert(observed_timeout == 1000,
      "datadir discovery did not use the explicit timeout")
  end)

  check("survives a datadir discovery spawn failure", function()
    error("test datadir spawn failure")
  end, function() end)

  if #failures > 0 then
    error(table.concat(failures, "\n\n"))
  end
end

local function run()
  assert(vim.fn.has("cscope") == 0)
  assert(vim.fn.exists(":Cscope") == 0)
  assert(vim.fn.exists(":GscopeFind") == 2)
  assert(package.loaded.cscope_maps == nil)
  check_failed_datadir_discovery()

  local auto_root = temp_root .. "/automatic"
  local auto_source = auto_root .. "/auto.c"
  vim.fn.mkdir(auto_root .. "/.git", "p")
  write(auto_source, { "int auto_symbol(void) { return 1; }" })
  local edited, edit_error = pcall(edit, auto_source)
  auto_buf = vim.api.nvim_get_current_buf()
  assert(edited, edit_error)
  local auto_db = assert(vim.b.gutentags_files.gtags_cscope)
  auto_cache_dir = vim.fs.dirname(auto_db)
  assert(auto_db:find(vim.fn.stdpath("cache") .. "/gutentags", 1, true) == 1)
  assert(vim.wait(30000, function()
    local current = jobs(auto_buf)
    return vim.fn.filereadable(auto_db) == 1
      and type(current) == "table" and #current == 0
  end, 100), "automatic GTAGS build timed out")
  cursor_on("auto_symbol")
  assert(require("gtags_adapter").find("g"))
  assert(vim.api.nvim_buf_get_name(0) == vim.fs.normalize(auto_source))

  write(auto_source, {
    "int auto_symbol(void) { return 1; }",
    "int auto_updated_symbol(void) { return 5; }",
  })
  make_newer(auto_source, auto_db)
  local auto_updates = 0
  local auto_update_starts = 0
  vim.api.nvim_create_autocmd("User", {
    pattern = "GutentagsUpdated",
    callback = function() auto_updates = auto_updates + 1 end,
  })
  vim.api.nvim_create_autocmd("User", {
    pattern = "GutentagsUpdating",
    callback = function() auto_update_starts = auto_update_starts + 1 end,
  })
  local auto_update_started
  vim.api.nvim_buf_call(auto_buf, function()
    auto_update_started = require("gtags_adapter").update()
  end)
  assert(auto_update_started)
  assert(vim.wait(30000, function()
    local current = jobs(auto_buf)
    return auto_updates > 0 and type(current) == "table" and #current == 0
  end, 100), "automatic GTAGS update timed out")
  local updated_lines = vim.fn.readfile(auto_source)
  assert(updated_lines[2] == "int auto_updated_symbol(void) { return 5; }",
    "automatic update changed the source fixture: " .. vim.inspect(updated_lines))
  vim.api.nvim_set_current_buf(auto_buf)
  vim.cmd("silent edit!")
  assert(vim.fn.search("auto_updated_symbol", "cw") > 0,
    "updated automatic symbol is missing from the buffer")
  cursor_on("auto_updated_symbol")
  assert(require("gtags_adapter").find("g"))
  assert(vim.api.nvim_buf_get_name(0) == vim.fs.normalize(auto_source))

  local live_manual_db = auto_root .. "/GTAGS"
  local built = vim.system({ "gtags" }, { cwd = auto_root, text = true }):wait()
  assert(built.code == 0, built.stderr)
  vim.api.nvim_set_current_buf(auto_buf)
  assert(vim.fn.search("auto_symbol", "cw") > 0,
    "automatic symbol is missing before live reclassification")
  cursor_on("auto_symbol")
  assert(require("gtags_adapter").find("g"))
  assert(vim.b.gutentags_hybrid_mode == "manual")
  assert(vim.b.gutentags_files.gtags_cscope == live_manual_db)

  local starts_before_save = auto_update_starts
  local updates_before_save = auto_updates
  vim.api.nvim_buf_set_lines(auto_buf, -1, -1, false, {
    "int live_manual_saved_symbol(void) { return 6; }",
  })
  vim.cmd("silent write")
  vim.wait(500)
  local transitioned_jobs = jobs(auto_buf)
  assert(type(transitioned_jobs) == "table" and #transitioned_jobs == 0,
    "live manual buffer started a Gutentags job")
  assert(auto_update_starts == starts_before_save,
    "live manual buffer invoked the stale Gutentags save hook")
  assert(auto_updates == updates_before_save,
    "live manual buffer completed an automatic Gutentags update")
  local stale_query = vim.system({ "global", "-x", "live_manual_saved_symbol" }, {
    cwd = auto_root,
    env = { GTAGSROOT = auto_root, GTAGSDBPATH = auto_root },
    text = true,
  }):wait()
  assert(not (stale_query.stdout or ""):find(
      "live_manual_saved_symbol", 1, true),
    "automatic save hook updated the live manual database: "
      .. (stale_query.stdout or ""))

  manual_root = temp_root .. "/manual"
  local manual_source = manual_root .. "/manual.c"
  write(manual_source, { "int manual_symbol(void) { return 2; }" })
  local built = vim.system({ "gtags" }, { cwd = manual_root, text = true }):wait()
  assert(built.code == 0, built.stderr)
  local cache_before_manual = cache_entries()
  edit(manual_source)
  assert(vim.b.gutentags_hybrid_mode == "manual")
  assert(vim.b.gutentags_files.gtags_cscope == manual_root .. "/GTAGS")
  vim.wait(300)
  local manual_jobs = jobs()
  assert(type(manual_jobs) == "table" and #manual_jobs == 0,
    "manual project started a Gutentags job")
  assert(vim.deep_equal(cache_before_manual, cache_entries()),
    "manual project created a cache database")
  cursor_on("manual_symbol")
  assert(require("gtags_adapter").find("g"))

  write(manual_source, {
    "int manual_symbol(void) { return 2; }",
    "int manual_updated_symbol(void) { return 3; }",
  })
  make_newer(manual_source, manual_root .. "/GTAGS")
  assert(require("gtags_adapter").update())
  assert(not require("gtags_adapter").update(), "duplicate manual update was accepted")
  assert(vim.wait(10000, function()
    local result = vim.system({ "global", "-x", "manual_updated_symbol" }, {
      cwd = manual_root,
      env = { GTAGSROOT = manual_root, GTAGSDBPATH = manual_root },
      text = true,
    }):wait()
    return result.code == 0 and (result.stdout or ""):find("manual_updated_symbol", 1, true)
  end, 100), "manual global update timed out")

  local corrupt_root = temp_root .. "/corrupt"
  local corrupt_source = corrupt_root .. "/corrupt.c"
  write(corrupt_root .. "/GTAGS", {})
  write(corrupt_source, { "int corrupt_symbol(void) { return 4; }" })
  edit(corrupt_source)
  assert(vim.b.gutentags_hybrid_mode == "manual")
  cursor_on("corrupt_symbol")
  local notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message, level)
    notifications[#notifications + 1] = { message = tostring(message), level = level }
  end
  local query_ok, query_result = xpcall(function()
    return require("gtags_adapter").find("g")
  end, debug.traceback)
  vim.notify = original_notify
  if not query_ok then
    error(query_result)
  end
  assert(not query_result, "corrupt GTAGS query unexpectedly succeeded")
  local failure
  for _, notification in ipairs(notifications) do
    if notification.level == vim.log.levels.WARN
        and notification.message:find("corrupted", 1, true) then
      failure = notification.message
      break
    end
  end
  assert(failure, "corrupt GTAGS query did not report the backend diagnostic")
  assert(failure:find(corrupt_root .. "/GTAGS", 1, true),
    "corrupt GTAGS diagnostic omitted the database path")
  assert(not failure:find("未找到", 1, true),
    "corrupt GTAGS query was reported as an empty result")

  local disabled_root = temp_root .. "/disabled"
  local disabled_source = disabled_root .. "/disabled.c"
  write(disabled_root .. "/.notags", {})
  write(disabled_source, { "int disabled_symbol;" })
  local cache_before_disabled = cache_entries()
  edit(disabled_source)
  assert(vim.b.gutentags_hybrid_mode == "disabled")
  assert(vim.b.gutentags_files == nil)
  vim.wait(300)
  local disabled_jobs = jobs()
  assert(type(disabled_jobs) == "table" and #disabled_jobs == 0,
    ".notags project started a Gutentags job")
  assert(vim.deep_equal(cache_before_disabled, cache_entries()),
    ".notags project created a cache database")
  assert(not require("gtags_adapter").update())
end

local function manual_update_running()
  if manual_root == nil then
    return false
  end
  local state = _G.NvimGutentagsHybridState
  assert(type(state) == "table", "adapter state is unavailable during cleanup")
  local updates = state.manual_updates
  assert(type(updates) == "table", "manual update state is unavailable during cleanup")
  return updates[manual_root] ~= nil
end

local function cleanup()
  local last_jobs, last_job_error = {}, nil
  local last_manual_update = false
  local quiescent = vim.wait(30000, function()
    if auto_buf then
      last_jobs, last_job_error = jobs(auto_buf)
    else
      last_jobs, last_job_error = {}, nil
    end
    if last_job_error then
      error("automatic job inspection failed: " .. last_job_error)
    end
    last_manual_update = manual_update_running()
    return type(last_jobs) == "table" and #last_jobs == 0
      and not last_manual_update
  end, 100)
  if not quiescent then
    error("writers did not quiesce; temporary project and cache fixtures were preserved: "
      .. vim.inspect({ automatic_jobs = last_jobs,
        automatic_job_error = last_job_error,
        manual_update = last_manual_update }))
  end

  local failures = {}
  local deleted, result = pcall(vim.fn.delete, temp_root, "rf")
  if not deleted or result ~= 0 then
    failures[#failures + 1] = "failed to delete temporary project fixtures: "
      .. tostring(result)
  end
  if auto_cache_dir then
    deleted, result = pcall(vim.fn.delete, auto_cache_dir, "rf")
    if not deleted or result ~= 0 then
      failures[#failures + 1] = "failed to delete automatic cache fixture: "
        .. tostring(result)
    end
  end
  if #failures > 0 then
    error(table.concat(failures, "\n"))
  end
end

local ok, err = xpcall(run, debug.traceback)
local cleanup_ok, cleanup_error = xpcall(cleanup, debug.traceback)
if not cleanup_ok then
  if ok then
    ok, err = false, "Cleanup failure:\n" .. tostring(cleanup_error)
  else
    err = tostring(err) .. "\n\nCleanup failure:\n" .. tostring(cleanup_error)
  end
end
if not ok then
  error(err, 0)
end
print("Gutentags integration test passed")
