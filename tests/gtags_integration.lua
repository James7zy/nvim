if not vim.g.lazy_did_setup then
  -- Neovim's -l mode skips user initialization and disables plugin loading.
  vim.go.loadplugins = true
  dofile(vim.fn.stdpath("config") .. "/init.lua")
end

local temp_root = vim.fn.tempname()
local auto_cache_dir
local auto_buf
local automatic_db
local blocked_gtags_release
local blocked_gtags_release_notags
local manual_root
local migrated_automatic_db
local migrated_cache_dir
local original_cache_dir
local original_gtags_executable
local original_gtags_started_env
local original_gtags_release_env
local notags_automatic_db
local notags_cache_dir
local transition_manual_db
vim.fn.mkdir(temp_root, "p")

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines or {}, path) == 0)
end

local function release_blocked_gtags()
  if blocked_gtags_release then
    write(blocked_gtags_release, {})
  end
  if blocked_gtags_release_notags then
    write(blocked_gtags_release_notags, {})
  end
  if original_gtags_executable then
    vim.g.gutentags_gtags_executable = original_gtags_executable
  end
  if original_cache_dir then
    vim.g.gutentags_cache_dir = original_cache_dir
  end
  if original_gtags_started_env ~= nil then
    vim.env.GTAGS_TEST_STARTED = original_gtags_started_env
  else
    vim.env.GTAGS_TEST_STARTED = nil
  end
  if original_gtags_release_env ~= nil then
    vim.env.GTAGS_TEST_RELEASE = original_gtags_release_env
  else
    vim.env.GTAGS_TEST_RELEASE = nil
  end
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

local function job_index(database)
  local ok, index = pcall(vim.fn["gutentags#find_job_index_by_tags_file"],
    "gtags_cscope", database)
  assert(ok, index)
  assert(type(index) == "number", "Gutentags returned an invalid job index")
  return index
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
  automatic_db = auto_db
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

  local real_gtags = assert(vim.fn.exepath("gtags"))
  local blocking_gtags = temp_root .. "/blocking-gtags"
  local blocked_gtags_started = temp_root .. "/blocking-gtags-started"
  blocked_gtags_release = temp_root .. "/blocking-gtags-release"
  write(blocking_gtags, {
    "#!/bin/sh",
    "set -eu",
    ": > \"${GTAGS_TEST_STARTED:?}\"",
    "while [ ! -e \"${GTAGS_TEST_RELEASE:?}\" ]; do sleep 0.05; done",
    "exec " .. vim.fn.shellescape(real_gtags) .. " \"$@\"",
  })
  assert(vim.uv.fs_chmod(blocking_gtags, 493))
  original_gtags_executable = vim.g.gutentags_gtags_executable
  original_cache_dir = vim.g.gutentags_cache_dir
  original_gtags_started_env = vim.env.GTAGS_TEST_STARTED
  original_gtags_release_env = vim.env.GTAGS_TEST_RELEASE
  vim.env.GTAGS_TEST_STARTED = blocked_gtags_started
  vim.env.GTAGS_TEST_RELEASE = blocked_gtags_release
  vim.g.gutentags_gtags_executable = blocking_gtags

  vim.api.nvim_set_current_buf(auto_buf)
  local starts_before_block = auto_update_starts
  local automatic_root = vim.b.gutentags_root
  local automatic_files = vim.deepcopy(vim.b.gutentags_files)
  assert(require("gtags_adapter").update())
  assert(vim.wait(10000, function()
    local current = jobs(auto_buf)
    return vim.fn.filereadable(blocked_gtags_started) == 1
      and type(current) == "table"
      and vim.tbl_contains(current, "gtags_cscope")
  end, 50), "blocking automatic GTAGS update did not start")

  vim.api.nvim_buf_set_lines(auto_buf, -1, -1, false, {
    "int queued_save_marker(void) { return 6; }",
  })
  vim.cmd("silent write")

  local live_manual_db = auto_root .. "/GTAGS"
  transition_manual_db = live_manual_db
  local built = vim.system({ real_gtags }, { cwd = auto_root, text = true }):wait()
  assert(built.code == 0, built.stderr)
  vim.api.nvim_buf_set_lines(auto_buf, -1, -1, false, {
    "int queued_race_symbol(void) { return 7; }",
  })
  vim.cmd("silent write")
  assert(auto_update_starts >= starts_before_block + 3,
    "automatic update and queued saves did not invoke Gutentags")
  assert(vim.fn.search("auto_symbol", "cw") > 0,
    "automatic symbol is missing before live reclassification")
  cursor_on("auto_symbol")
  migrated_cache_dir = temp_root .. "/migrated-cache"
  vim.g.gutentags_cache_dir = migrated_cache_dir
  local generate_on_missing = vim.g.gutentags_generate_on_missing
  local generate_on_new = vim.g.gutentags_generate_on_new
  vim.g.gutentags_generate_on_missing = 0
  vim.g.gutentags_generate_on_new = 0
  local rescan_ok, rescan_error = pcall(vim.fn["gutentags#rescan"])
  vim.g.gutentags_generate_on_missing = generate_on_missing
  vim.g.gutentags_generate_on_new = generate_on_new
  assert(rescan_ok, rescan_error)
  assert(vim.b.gutentags_hybrid_mode == "automatic",
    "active rescan changed the hybrid mode")
  assert(vim.b.gutentags_root == automatic_root,
    "active rescan changed the automatic root")
  local migrated_files = vim.deepcopy(vim.b.gutentags_files)
  migrated_automatic_db = assert(migrated_files.gtags_cscope)
  assert(migrated_automatic_db ~= automatic_db,
    "rescan did not migrate the automatic cache target")
  assert(job_index(migrated_automatic_db) < 0
      and job_index(automatic_db) >= 0,
    "cache migration did not leave only the old target active")
  vim.wait(100)
  assert(vim.b.gutentags_hybrid_mode == "automatic",
    "scheduled active rescan changed the hybrid mode")
  assert(vim.deep_equal(vim.b.gutentags_files, migrated_files),
    "scheduled active rescan changed migrated cache metadata")

  local transition_notifications = {}
  local original_notify = vim.notify
  vim.notify = function(message, level)
    transition_notifications[#transition_notifications + 1] = {
      message = tostring(message), level = level,
    }
  end
  local transition_ok, transition_result = xpcall(function()
    return require("gtags_adapter").find("g")
  end, debug.traceback)
  vim.notify = original_notify
  assert(transition_ok, transition_result)
  assert(not transition_result,
    "active automatic work allowed a live manual transition")
  assert(transition_notifications[#transition_notifications].message:find(
    "稍后重试", 1, true), "transition failure did not request a retry")
  vim.wait(100)
  assert(vim.b.gutentags_hybrid_mode == "automatic")
  assert(vim.b.gutentags_root == automatic_root)
  assert(vim.deep_equal(vim.b.gutentags_files, migrated_files),
    "deferred transition changed automatic database metadata")
  local write_hooks = vim.api.nvim_get_autocmds({
    group = "gutentags_buffer_" .. auto_buf,
    event = "BufWritePost",
    buffer = auto_buf,
  })
  assert(#write_hooks == 1,
    "deferred transition detached the automatic write hook")

  assert(not require("gtags_adapter").find("g"),
    "idle migrated target hid the active old-cache writer")
  vim.wait(100)
  assert(vim.b.gutentags_hybrid_mode == "automatic",
    "old-cache writer did not block the migrated transition")
  assert(vim.deep_equal(vim.b.gutentags_files, migrated_files),
    "old-cache writer changed migrated cache metadata")

  local gap_rescans = 0
  local gap_snapshot
  local gap_group = vim.api.nvim_create_augroup(
    "gtags_integration_rescan_gap", { clear = true }
  )
  vim.api.nvim_create_autocmd("User", {
    group = gap_group,
    pattern = "GutentagsUpdated",
    callback = function()
      if gap_rescans > 0 then
        return
      end
      gap_rescans = gap_rescans + 1
      vim.api.nvim_buf_call(auto_buf, function()
        vim.fn["gutentags#rescan"]()
        gap_snapshot = {
          files = vim.deepcopy(vim.b.gutentags_files),
          mode = vim.b.gutentags_hybrid_mode,
          root = vim.b.gutentags_root,
        }
      end)
    end,
  })
  local updates_before_release = auto_updates
  vim.g.gutentags_gtags_executable = original_gtags_executable
  write(blocked_gtags_release, {})
  assert(vim.wait(30000, function()
    return auto_updates >= updates_before_release + 2
      and job_index(automatic_db) < 0
      and job_index(migrated_automatic_db) < 0
  end, 50), "blocked and queued automatic GTAGS updates did not drain")
  assert(gap_rescans == 1, "queued replay did not exercise rescan completion gap")
  assert(gap_snapshot.mode == "automatic",
    "completion-gap rescan changed the hybrid mode")
  assert(gap_snapshot.root == automatic_root,
    "completion-gap rescan changed the automatic root")
  assert(vim.deep_equal(gap_snapshot.files, migrated_files),
    "completion-gap rescan did not restore automatic cache metadata")
  assert(vim.b.gutentags_hybrid_mode == "automatic",
    "queued replay completion changed the hybrid mode")
  assert(vim.deep_equal(vim.b.gutentags_files, migrated_files),
    "queued replay completion changed automatic cache metadata")
  pcall(vim.api.nvim_del_augroup_by_name, "gtags_integration_rescan_gap")
  release_blocked_gtags()
  blocked_gtags_release = nil

  assert(not require("gtags_adapter").find("g"),
    "quiescent migrated target was not staged for adoption")
  assert(vim.b.gutentags_hybrid_mode == "automatic")
  vim.wait(100)
  assert(vim.b.gutentags_hybrid_mode == "automatic",
    "candidate target transitioned without an exact follow-up pass")
  assert(not require("gtags_adapter").find("g"),
    "exact migrated-target pass did not defer metadata mutation")
  assert(vim.wait(1000, function()
    return vim.b[auto_buf].gutentags_hybrid_mode == "manual"
  end, 10), "scheduled live manual transition did not complete")
  assert(vim.b.gutentags_files.gtags_cscope == live_manual_db)
  cursor_on("auto_symbol")
  assert(require("gtags_adapter").find("g"))

  local stale_query = vim.system({ "global", "-x", "queued_race_symbol" }, {
    cwd = auto_root,
    env = { GTAGSROOT = auto_root, GTAGSDBPATH = auto_root },
    text = true,
  }):wait()
  assert(not (stale_query.stdout or ""):find(
      "queued_race_symbol", 1, true),
    "queued automatic replay updated the live manual database: "
      .. (stale_query.stdout or ""))
  make_newer(auto_source, live_manual_db)
  assert(require("gtags_adapter").update())
  assert(vim.wait(10000, function()
    local result = vim.system({ "global", "-x", "queued_race_symbol" }, {
      cwd = auto_root,
      env = { GTAGSROOT = auto_root, GTAGSDBPATH = auto_root },
      text = true,
    }):wait()
    return (result.stdout or ""):find("queued_race_symbol", 1, true) ~= nil
  end, 100), "explicit manual update did not index the queued-race symbol")

  local notags_root = temp_root .. "/notags-live"
  local notags_source = notags_root .. "/notags.c"
  vim.fn.mkdir(notags_root .. "/.git", "p")
  write(notags_source, { "int notags_live_symbol(void) { return 8; }" })
  edit(notags_source)
  local notags_buf = vim.api.nvim_get_current_buf()
  notags_automatic_db = assert(vim.b.gutentags_files.gtags_cscope)
  notags_cache_dir = vim.fs.dirname(notags_automatic_db)
  assert(vim.wait(30000, function()
    return vim.fn.filereadable(notags_automatic_db) == 1
      and job_index(notags_automatic_db) < 0
  end, 50), ".notags automatic fixture build timed out")
  local trusted_notags_files = vim.deepcopy(vim.b.gutentags_files)
  local notags_user_writes = 0
  local notags_user_group = vim.api.nvim_create_augroup(
    "gtags_integration_notags_user", { clear = true }
  )
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = notags_user_group,
    buffer = notags_buf,
    callback = function() notags_user_writes = notags_user_writes + 1 end,
  })

  local notags_started = temp_root .. "/notags-gtags-started"
  blocked_gtags_release_notags = temp_root .. "/notags-gtags-release"
  vim.env.GTAGS_TEST_STARTED = notags_started
  vim.env.GTAGS_TEST_RELEASE = blocked_gtags_release_notags
  vim.g.gutentags_gtags_executable = blocking_gtags
  assert(require("gtags_adapter").update())
  assert(vim.wait(10000, function()
    return vim.fn.filereadable(notags_started) == 1
      and job_index(notags_automatic_db) >= 0
  end, 50), ".notags blocking update did not start")
  vim.api.nvim_buf_set_lines(notags_buf, -1, -1, false, {
    "int notags_queued_symbol(void) { return 9; }",
  })
  vim.cmd("silent write")
  write(notags_root .. "/.notags", {})
  vim.fn["gutentags#rescan"]()
  assert(vim.b.gutentags_hybrid_mode == "automatic",
    ".notags rescan changed mode while automatic work was active")
  assert(vim.b.gutentags_root == notags_root,
    ".notags rescan changed the trusted automatic root")
  assert(vim.deep_equal(vim.b.gutentags_files, trusted_notags_files),
    ".notags rescan did not restore trusted automatic metadata")
  local notags_hooks = vim.api.nvim_get_autocmds({
    group = "gutentags_buffer_" .. notags_buf,
    event = "BufWritePost",
    buffer = notags_buf,
  })
  assert(#notags_hooks == 1,
    ".notags rescan detached the automatic hook before drain")
  vim.wait(100)
  assert(vim.b.gutentags_hybrid_mode == "automatic")

  local notags_updates_before_release = auto_updates
  vim.g.gutentags_gtags_executable = original_gtags_executable
  write(blocked_gtags_release_notags, {})
  assert(vim.wait(30000, function()
    return auto_updates >= notags_updates_before_release + 2
      and job_index(notags_automatic_db) < 0
  end, 50), ".notags blocked and queued updates did not drain")
  release_blocked_gtags()
  blocked_gtags_release_notags = nil
  assert(not require("gtags_adapter").update())
  assert(vim.wait(1000, function()
    return vim.b[notags_buf].gutentags_hybrid_mode == "disabled"
  end, 10), ".notags transition did not reach disabled mode")
  assert(vim.b.gutentags_root == nil)
  assert(vim.b.gutentags_files == nil)
  notags_hooks = vim.api.nvim_get_autocmds({
    group = "gutentags_buffer_" .. notags_buf,
    event = "BufWritePost",
    buffer = notags_buf,
  })
  assert(#notags_hooks == 0,
    ".notags disabled transition retained the automatic hook")
  local notags_user_writes_before_check = notags_user_writes
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = notags_buf })
  assert(notags_user_writes == notags_user_writes_before_check + 1,
    ".notags disabled transition removed the unrelated user hook")

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
  local state = _G.NvimGutentagsHybridState
  assert(type(state) == "table", "adapter state is unavailable during cleanup")
  local updates = state.manual_updates
  assert(type(updates) == "table", "manual update state is unavailable during cleanup")
  return next(updates) ~= nil
end

local function cleanup()
  release_blocked_gtags()
  local last_jobs, last_job_error = {}, nil
  local last_path_jobs = {}
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
    last_path_jobs = {}
    for _, database in ipairs({
      automatic_db, migrated_automatic_db, notags_automatic_db,
      transition_manual_db,
    }) do
      if database then
        local ok, index = pcall(vim.fn["gutentags#find_job_index_by_tags_file"],
          "gtags_cscope", database)
        if not ok then
          error("Gutentags path job inspection failed: " .. tostring(index))
        end
        if index >= 0 then
          last_path_jobs[#last_path_jobs + 1] = database
        end
      end
    end
    last_manual_update = manual_update_running()
    return type(last_jobs) == "table" and #last_jobs == 0
      and #last_path_jobs == 0
      and not last_manual_update
  end, 100)
  if not quiescent then
    error("writers did not quiesce; temporary project and cache fixtures were preserved: "
      .. vim.inspect({ automatic_jobs = last_jobs,
        automatic_job_error = last_job_error,
        path_jobs = last_path_jobs,
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
  if notags_cache_dir then
    deleted, result = pcall(vim.fn.delete, notags_cache_dir, "rf")
    if not deleted or result ~= 0 then
      failures[#failures + 1] = "failed to delete .notags cache fixture: "
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
