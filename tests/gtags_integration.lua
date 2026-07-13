if not vim.g.lazy_did_setup then
  -- Neovim's -l mode skips user initialization and disables plugin loading.
  vim.go.loadplugins = true
  dofile(vim.fn.stdpath("config") .. "/init.lua")
end

local temp_root = vim.fn.tempname()
local auto_cache_dir
vim.fn.mkdir(temp_root, "p")

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines or {}, path) == 0)
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

local function jobs()
  local ok, current = pcall(vim.fn["gutentags#inprogress"])
  return ok and type(current) == "table" and current or {}
end

local function cache_entries()
  local entries = vim.fn.glob(vim.fn.stdpath("cache") .. "/gutentags/*", false, true)
  table.sort(entries)
  return entries
end

local function run()
  assert(vim.fn.has("cscope") == 0)
  assert(vim.fn.exists(":Cscope") == 0)
  assert(vim.fn.exists(":GscopeFind") == 2)
  assert(package.loaded.cscope_maps == nil)

  local auto_root = temp_root .. "/automatic"
  local auto_source = auto_root .. "/auto.c"
  vim.fn.mkdir(auto_root .. "/.git", "p")
  write(auto_source, { "int auto_symbol(void) { return 1; }" })
  edit(auto_source)
  local auto_db = assert(vim.b.gutentags_files.gtags_cscope)
  auto_cache_dir = vim.fs.dirname(auto_db)
  assert(auto_db:find(vim.fn.stdpath("cache") .. "/gutentags", 1, true) == 1)
  assert(vim.wait(30000, function()
    return vim.fn.filereadable(auto_db) == 1 and #jobs() == 0
  end, 100), "automatic GTAGS build timed out")
  cursor_on("auto_symbol")
  assert(require("gtags_adapter").find("g"))
  assert(vim.api.nvim_buf_get_name(0) == vim.fs.normalize(auto_source))

  local auto_updates = 0
  vim.api.nvim_create_autocmd("User", {
    pattern = "GutentagsUpdated",
    callback = function() auto_updates = auto_updates + 1 end,
  })
  assert(require("gtags_adapter").update())
  assert(vim.wait(30000, function()
    return auto_updates > 0 and #jobs() == 0
  end, 100), "automatic GTAGS update timed out")

  local manual_root = temp_root .. "/manual"
  local manual_source = manual_root .. "/manual.c"
  write(manual_source, { "int manual_symbol(void) { return 2; }" })
  local built = vim.system({ "gtags" }, { cwd = manual_root, text = true }):wait()
  assert(built.code == 0, built.stderr)
  local cache_before_manual = cache_entries()
  edit(manual_source)
  assert(vim.b.gutentags_hybrid_mode == "manual")
  assert(vim.b.gutentags_files.gtags_cscope == manual_root .. "/GTAGS")
  vim.wait(300)
  assert(#jobs() == 0, "manual project started a Gutentags job")
  assert(vim.deep_equal(cache_before_manual, cache_entries()),
    "manual project created a cache database")
  cursor_on("manual_symbol")
  assert(require("gtags_adapter").find("g"))

  local database_mtime = assert(vim.uv.fs_stat(manual_root .. "/GTAGS")).mtime.sec
  assert(vim.wait(2000, function()
    return os.time() > database_mtime
  end, 10), "clock did not advance past the initial GTAGS build")
  write(manual_source, {
    "int manual_symbol(void) { return 2; }",
    "int manual_updated_symbol(void) { return 3; }",
  })
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
  assert(#jobs() == 0, ".notags project started a Gutentags job")
  assert(vim.deep_equal(cache_before_disabled, cache_entries()),
    ".notags project created a cache database")
  assert(not require("gtags_adapter").update())
end

local ok, err = xpcall(run, debug.traceback)
vim.fn.delete(temp_root, "rf")
if auto_cache_dir then
  vim.fn.delete(auto_cache_dir, "rf")
end
if not ok then
  error(err)
end
print("Gutentags integration test passed")
