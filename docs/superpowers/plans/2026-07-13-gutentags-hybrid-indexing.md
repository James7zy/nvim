# Gutentags Hybrid Indexing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `cscope_maps.nvim` with a unified Gutentags adapter that automatically maintains normal-project indexes, reuses in-tree GTAGS databases for large projects, and presents results through fzf-lua.

**Architecture:** `lua/plugins/gtags.lua` loads the Neovim-compatible Skywind Gutentags fork and `gutentags_plus` before the first file event. A focused `lua/gtags_adapter.lua` installs the `g:gutentags_init_user_func` guard, resolves manual/disabled/automatic modes, routes `GscopeFind!` quickfix results, and dispatches index updates. Native headless tests exercise the adapter with real files and Neovim commands; a full-config integration test exercises the actual Vimscript plugins and GNU GLOBAL tools.

**Tech Stack:** Neovim 0.12 Lua API, lazy.nvim, `skywind3000/vim-gutentags`, `skywind3000/gutentags_plus`, fzf-lua, GNU GLOBAL 6.6+, native headless Lua tests.

---

## File Map

- Create `lua/gtags_adapter.lua`: hybrid project classification, Gutentags pre-init hook, query result routing, keymaps, and update dispatch.
- Create `tests/gtags_adapter_spec.lua`: fast headless behavioral tests with real temporary files and minimal external-boundary doubles.
- Create `tests/gtags_integration.lua`: full-config automatic/manual/disabled integration test against real plugins and GNU GLOBAL.
- Modify `lua/plugins/gtags.lua`: replace cscope_maps with the compatible Gutentags stack and pre-load globals.
- Modify `lua/plugins/telescope.lua`: remove the obsolete comment that says GTAGS results still depend on cscope_maps/Telescope.
- Modify `lazy-lock.json`: remove `cscope_maps.nvim`; lock `vim-gutentags` and `gutentags_plus`.
- Modify `README.md`: document architecture, mode priority, dependencies, keys, updates, and recovery.

## Shared Test Command

Fast adapter tests run from the repository root:

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
```

Expected success suffix:

```text
All gtags adapter tests passed
```

Full-config commands must point Neovim at the worktree rather than the user's dirty primary checkout:

```bash
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless "+Lazy! install" +qa
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless -l tests/gtags_integration.lua
```

## Task 1: Hybrid Project Detection And Pre-Init Guard

**Files:**
- Create: `tests/gtags_adapter_spec.lua`
- Create: `lua/gtags_adapter.lua`

- [ ] **Step 1: Write the failing mode-selection tests**

Create `tests/gtags_adapter_spec.lua` with a small native harness. The tests use real temporary directories so they verify filesystem precedence rather than a mocked classifier.

```lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.g.mapleader = " "

local tests = {}
local failures = {}
local temp_root = vim.fn.tempname()
vim.fn.mkdir(temp_root, "p")

local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error((message or "values differ")
      .. "\nexpected: " .. vim.inspect(expected)
      .. "\nactual:   " .. vim.inspect(actual))
  end
end

local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  assert(vim.fn.writefile(lines or {}, path) == 0)
end

local function edit(path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  vim.b.gutentags_root = nil
  vim.b.gutentags_files = nil
  vim.b.gutentags_hybrid_mode = nil
  vim.b.gutentags_hybrid_root = nil
end

local existing_hook_calls = 0
vim.g.existing_gutentags_hook_result = 1
_G.ExistingGutentagsHook = function()
  existing_hook_calls = existing_hook_calls + 1
  return vim.g.existing_gutentags_hook_result
end
vim.cmd([[
  function! ExistingGutentagsHook(path) abort
    return v:lua.ExistingGutentagsHook(a:path)
  endfunction
]])
vim.g.gutentags_init_user_func = "ExistingGutentagsHook"

local adapter = require("gtags_adapter")
adapter.setup()

local function guard(path)
  return vim.fn.call(vim.g.gutentags_init_user_func, { path })
end

test("uses an in-tree GTAGS database and vetoes automatic indexing", function()
  local root = temp_root .. "/manual"
  local source = root .. "/src/manual.c"
  write(root .. "/GTAGS", { "test database" })
  write(source, { "int manual_symbol(void) { return 1; }" })
  edit(source)

  eq(0, guard(source))
  eq("manual", vim.b.gutentags_hybrid_mode)
  eq(root, vim.b.gutentags_root)
  eq(root .. "/GTAGS", vim.b.gutentags_files.gtags_cscope)
end)

test("stops at a nested project boundary before a parent GTAGS", function()
  local parent = temp_root .. "/nested-parent"
  local child = parent .. "/child"
  local source = child .. "/nested.c"
  write(parent .. "/GTAGS", { "parent database" })
  vim.fn.mkdir(child .. "/.git", "p")
  write(source, { "int nested_symbol;" })
  edit(source)

  eq(1, guard(source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(child, vim.b.gutentags_hybrid_root)
  eq(nil, vim.b.gutentags_files)
end)

test("vetoes automatic indexing at a .notags boundary", function()
  local root = temp_root .. "/disabled"
  local source = root .. "/disabled.c"
  write(root .. "/.notags", {})
  write(source, { "int disabled_symbol;" })
  edit(source)

  eq(0, guard(source))
  eq("disabled", vim.b.gutentags_hybrid_mode)
  eq(root, vim.b.gutentags_hybrid_root)
end)

test("allows Gutentags at a normal project marker", function()
  local root = temp_root .. "/automatic"
  local source = root .. "/automatic.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int automatic_symbol;" })
  edit(source)

  eq(1, guard(source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(root, vim.b.gutentags_hybrid_root)
end)

test("clears a stale manual database when the project mode changes", function()
  local root = temp_root .. "/mode-transition"
  local source = root .. "/transition.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(root .. "/GTAGS", { "manual database" })
  write(source, { "int transition_symbol;" })
  edit(source)

  eq(0, guard(source))
  eq("manual", vim.b.gutentags_hybrid_mode)
  assert(vim.fn.delete(root .. "/GTAGS") == 0)
  eq(1, guard(source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(nil, vim.b.gutentags_root)
  eq(nil, vim.b.gutentags_files)
end)

test("chains an existing Gutentags init hook", function()
  local root = temp_root .. "/existing-hook"
  local source = root .. "/hook.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int hook_symbol;" })
  edit(source)
  local before = existing_hook_calls

  vim.g.existing_gutentags_hook_result = 0
  eq(0, guard(source))
  eq(before + 1, existing_hook_calls)
  vim.g.existing_gutentags_hook_result = 1
end)

local function run()
  for _, item in ipairs(tests) do
    local ok, err = xpcall(item.fn, debug.traceback)
    if ok then
      print("PASS " .. item.name)
    else
      failures[#failures + 1] = item.name .. "\n" .. err
      print("FAIL " .. item.name)
    end
  end
  vim.fn.delete(temp_root, "rf")
  if #failures > 0 then
    error(table.concat(failures, "\n\n"))
  end
  print("All gtags adapter tests passed")
end

run()
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
```

Expected: failure containing `module 'gtags_adapter' not found`.

- [ ] **Step 3: Implement the minimal classifier and hook**

Create `lua/gtags_adapter.lua`:

```lua
local M = {}

local root_markers = {
  ".git", ".hg", ".svn", ".bzr", "_darcs", "_FOSSIL_", ".fslckout",
  ".root", ".project",
}

local configured = false
local previous_init_hook

local function exists(path)
  return (vim.uv or vim.loop).fs_stat(path) ~= nil
end

local function start_dir(path)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  if stat and stat.type == "directory" then
    return vim.fs.normalize(path)
  end
  return vim.fs.dirname(vim.fs.normalize(path))
end

local function classify(path)
  local dir = start_dir(path)
  while dir and dir ~= "" do
    local database = dir .. "/GTAGS"
    if exists(database) then
      return { mode = "manual", root = dir, database = database }
    end
    if exists(dir .. "/.notags") then
      return { mode = "disabled", root = dir }
    end
    for _, marker in ipairs(root_markers) do
      if exists(dir .. "/" .. marker) then
        return { mode = "automatic", root = dir }
      end
    end
    local parent = vim.fs.dirname(dir)
    if not parent or parent == dir then
      break
    end
    dir = parent
  end
  return { mode = "unconfigured" }
end

local function apply_context(context)
  local previous_mode = vim.b.gutentags_hybrid_mode
  local must_clear = context.mode == "disabled"
    or context.mode == "unconfigured"
    or (context.mode == "automatic" and previous_mode == "manual")
  if must_clear then
    vim.b.gutentags_root = nil
    vim.b.gutentags_files = nil
  end
  vim.b.gutentags_hybrid_mode = context.mode
  vim.b.gutentags_hybrid_root = context.root
  if context.mode ~= "manual" then
    return
  end
  local files = type(vim.b.gutentags_files) == "table"
      and vim.deepcopy(vim.b.gutentags_files) or {}
  files.gtags_cscope = context.database
  vim.b.gutentags_root = context.root
  vim.b.gutentags_files = files
end

local function hybrid_guard(path)
  local context = classify(path)
  apply_context(context)
  return (context.mode == "manual" or context.mode == "disabled") and 0 or 1
end

function M.setup()
  if configured then
    return
  end
  configured = true
  previous_init_hook = vim.g.gutentags_init_user_func

  _G.NvimGutentagsHybridGuard = function(path)
    if type(previous_init_hook) == "string"
        and previous_init_hook ~= ""
        and previous_init_hook ~= "GutentagsHybridGuard" then
      local ok, allowed = pcall(vim.fn.call, previous_init_hook, { path })
      if not ok or tonumber(allowed) == 0 then
        return 0
      end
    end
    return hybrid_guard(path)
  end

  vim.cmd([[
    function! GutentagsHybridGuard(path) abort
      return v:lua.NvimGutentagsHybridGuard(a:path)
    endfunction
  ]])
  vim.g.gutentags_init_user_func = "GutentagsHybridGuard"
end

return M
```

- [ ] **Step 4: Run the test to verify GREEN**

Run:

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
```

Expected: six `PASS` lines followed by `All gtags adapter tests passed`.

- [ ] **Step 5: Commit Task 1**

```bash
git add lua/gtags_adapter.lua tests/gtags_adapter_spec.lua
git commit -m "feat(gtags): add hybrid project detection"
```

## Task 2: Unified Queries, Result Routing, And Keymaps

**Files:**
- Modify: `tests/gtags_adapter_spec.lua`
- Modify: `lua/gtags_adapter.lua`

- [ ] **Step 1: Add failing query behavior tests**

Before `local function run()` in `tests/gtags_adapter_spec.lua`, add a real user-command boundary for `GscopeFind` and tests for zero, one, and multiple locations:

```lua
local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = tostring(message), level = level }
end

local query_items = {}
local last_query
vim.api.nvim_create_user_command("GscopeFind", function(opts)
  last_query = { args = opts.fargs, bang = opts.bang }
  vim.fn.setqflist({}, "r", { title = "test GscopeFind", items = query_items })
end, { nargs = "+", bang = true })

local fzf_calls = 0
package.loaded["fzf-lua"] = {
  quickfix = function(opts)
    fzf_calls = fzf_calls + 1
    eq(true, opts.valid_only)
  end,
}

local function manual_query_fixture(name)
  local root = temp_root .. "/query-" .. name
  local source = root .. "/source.c"
  write(root .. "/GTAGS", { "test database" })
  write(source, { "int query_symbol(void) { return 1; }" })
  edit(source)
  return root, source
end

write(temp_root .. "/autoload/gutentags.vim", {
  "function! gutentags#inprogress() abort",
  "  return get(g:, 'test_gutentags_jobs', [])",
  "endfunction",
})
vim.opt.runtimepath:prepend(temp_root)

test("reports an empty query without opening fzf", function()
  manual_query_fixture("empty")
  query_items = { { text = '[cscope g: definition of "query_symbol"]' } }
  local before_fzf = fzf_calls

  eq(false, adapter.find("g"))
  eq(before_fzf, fzf_calls)
  assert(notifications[#notifications].message:find("未找到", 1, true))
end)

test("jumps directly when a query has one valid location", function()
  local root = manual_query_fixture("single")
  local target = root .. "/target.c"
  write(target, { "", "int query_symbol(void) { return 2; }" })
  query_items = {
    { text = '[cscope g: definition of "query_symbol"]' },
    { filename = target, lnum = 2, col = 1, text = "query_symbol" },
  }

  eq(true, adapter.find("g"))
  eq({ "g", "query_symbol" }, last_query.args)
  eq(true, last_query.bang)
  eq(vim.fs.normalize(target), vim.api.nvim_buf_get_name(0))
  eq(2, vim.api.nvim_win_get_cursor(0)[1])
end)

test("opens fzf-lua for multiple valid locations", function()
  local root = manual_query_fixture("multiple")
  local first = root .. "/first.c"
  local second = root .. "/second.c"
  write(first, { "int query_symbol;" })
  write(second, { "int query_symbol;" })
  query_items = {
    { text = '[cscope s: symbol "query_symbol"]' },
    { filename = first, lnum = 1, col = 1, text = "first" },
    { filename = second, lnum = 1, col = 1, text = "second" },
  }
  local before_fzf = fzf_calls

  eq(true, adapter.find("s"))
  eq(before_fzf + 1, fzf_calls)
  eq(2, #vim.fn.getqflist())
end)

test("surfaces a line-zero database error instead of opening fzf", function()
  manual_query_fixture("corrupt")
  query_items = {
    { text = '[cscope g: definition of "query_symbol"]' },
    { text = "GTAGS corrupted", lnum = 0 },
  }

  eq(false, adapter.find("g"))
  assert(notifications[#notifications].message:find("GTAGS corrupted", 1, true))
end)

test("blocks automatic queries while Gutentags is running", function()
  local root = temp_root .. "/query-busy"
  local source = root .. "/source.c"
  local database = temp_root .. "/query-busy-cache/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int query_symbol(void) { return 1; }" })
  write(database, { "test database" })
  edit(source)
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = database }
  vim.g.test_gutentags_jobs = { "gtags_cscope" }

  eq(false, adapter.find("g"))
  assert(notifications[#notifications].message:find("正在生成或更新", 1, true))
  vim.g.test_gutentags_jobs = {}
end)

test("reports tools missing from the query action", function()
  manual_query_fixture("missing-tools")
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.find("g"))
    assert(notifications[#notifications].message:find("global", 1, true))
    assert(notifications[#notifications].message:find("gtags-cscope", 1, true))
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("installs the existing leader-g query maps", function()
  for _, suffix in ipairs({ "d", "s", "r", "t", "e", "f", "i" }) do
    local mapping = vim.fn.maparg("<leader>g" .. suffix, "n", false, true)
    assert(type(mapping) == "table" and mapping.desc,
      "missing map <leader>g" .. suffix)
  end
end)
```

- [ ] **Step 2: Run the test to verify RED**

Run the shared fast test command. Expected: failure `attempt to call field 'find' (a nil value)`; the keymap test must also fail before production code is added.

- [ ] **Step 3: Implement query routing and keymaps**

In `lua/gtags_adapter.lua`, add these private helpers above `M.setup()`:

```lua
local manual_updates = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "GTAGS" })
end

local function current_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or vim.bo[bufnr].buftype ~= "" or vim.fn.filereadable(path) ~= 1 then
    return nil, "当前 buffer 不是可查询的普通文件"
  end
  local context = classify(path)
  apply_context(context)
  if context.mode == "automatic" then
    local files = vim.b.gutentags_files
    local database = type(files) == "table" and files.gtags_cscope or nil
    if type(database) ~= "string" or database == "" then
      return nil, "Gutentags 尚未为当前项目准备数据库"
    end
    context.root = vim.b.gutentags_root or context.root
    context.database = database
  end
  if context.mode == "disabled" then
    return nil, context.root .. " 包含 .notags；请先手动生成 GTAGS"
  end
  if context.mode == "unconfigured" then
    return nil, "找不到项目根；请在项目根创建 .root"
  end
  return context
end

local function missing_tools(tools)
  local missing = {}
  for _, tool in ipairs(tools) do
    if vim.fn.executable(tool) ~= 1 then
      missing[#missing + 1] = tool
    end
  end
  return missing
end

local function automatic_update_running()
  local ok, jobs = pcall(vim.fn["gutentags#inprogress"])
  return ok and type(jobs) == "table" and vim.tbl_contains(jobs, "gtags_cscope")
end

local function query_term(kind)
  return vim.fn.expand((kind == "f" or kind == "i") and "<cfile>" or "<cword>")
end

local function split_quickfix(items)
  local locations, errors = {}, {}
  for _, item in ipairs(items) do
    local is_title = type(item.text) == "string" and item.text:match("^%[cscope ")
    if item.valid == 1 and item.bufnr > 0 and item.lnum > 0 then
      locations[#locations + 1] = item
    elseif not is_title and type(item.text) == "string" and item.text ~= "" then
      errors[#errors + 1] = item.text
    end
  end
  return locations, errors
end

local function setup_keymaps()
  local maps = {
    d = { "g", "定义" }, s = { "s", "符号/引用" }, r = { "c", "调用者" },
    t = { "t", "文本" }, e = { "e", "egrep" }, f = { "f", "文件" },
    i = { "i", "include" },
  }
  for suffix, value in pairs(maps) do
    vim.keymap.set("n", "<leader>g" .. suffix, function()
      M.find(value[1])
    end, { silent = true, desc = "GTAGS: " .. value[2] })
  end
end
```

Add `M.find` before `M.setup`:

```lua
function M.find(kind)
  local context, context_error = current_context()
  if not context then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
  local missing = missing_tools({ "global", "gtags-cscope" })
  if #missing > 0 then
    notify("缺少查询命令: " .. table.concat(missing, ", "), vim.log.levels.ERROR)
    return false
  end
  if context.mode == "automatic" and automatic_update_running() then
    notify("Gutentags 正在生成或更新索引，请稍后再查询", vim.log.levels.WARN)
    return false
  end
  if context.mode == "manual" and manual_updates[context.root] then
    notify("当前手动索引正在更新，请稍后再查询", vim.log.levels.WARN)
    return false
  end
  if vim.fn.filereadable(context.database) ~= 1 then
    notify("GTAGS 数据库尚未就绪: " .. context.database, vim.log.levels.WARN)
    return false
  end
  local term = query_term(kind)
  if term == "" then
    notify("光标下没有可查询的符号", vim.log.levels.WARN)
    return false
  end
  if vim.fn.exists(":GscopeFind") ~= 2 then
    notify("GscopeFind 命令不可用", vim.log.levels.ERROR)
    return false
  end

  local ok = pcall(vim.api.nvim_cmd, {
    cmd = "GscopeFind", args = { kind, term }, bang = true,
  }, {})
  if not ok then
    notify("GTAGS 查询失败；数据库: " .. context.database .. "；请查看 :messages",
      vim.log.levels.ERROR)
    return false
  end

  local locations, errors = split_quickfix(vim.fn.getqflist())
  if #locations == 0 then
    local detail = errors[1] or ("未找到: " .. term)
    notify(detail .. "；数据库: " .. context.database, vim.log.levels.WARN)
    return false
  end

  vim.fn.setqflist({}, "r", {
    title = "GTAGS " .. kind .. ": " .. term,
    items = locations,
  })
  if #locations == 1 then
    vim.cmd("cfirst")
    return true
  end
  local loaded, fzf = pcall(require, "fzf-lua")
  if not loaded then
    notify("fzf-lua 不可用", vim.log.levels.ERROR)
    return false
  end
  fzf.quickfix({ valid_only = true })
  return true
end
```

At the end of `M.setup()`, after assigning `g:gutentags_init_user_func`, call:

```lua
  setup_keymaps()
```

- [ ] **Step 4: Run the test to verify GREEN**

Run the shared fast test command. Expected: all mode, query, error, and keymap tests pass.

- [ ] **Step 5: Commit Task 2**

```bash
git add lua/gtags_adapter.lua tests/gtags_adapter_spec.lua
git commit -m "feat(gtags): route queries through fzf-lua"
```

## Task 3: Automatic And Manual Index Updates

**Files:**
- Modify: `tests/gtags_adapter_spec.lua`
- Modify: `lua/gtags_adapter.lua`

- [ ] **Step 1: Add failing update tests**

Before `local function run()` in the test file, add:

```lua
test("dispatches automatic updates to the buffer-local Gutentags command", function()
  local root = temp_root .. "/update-auto"
  local source = root .. "/auto.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int auto_update_symbol;" })
  edit(source)
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = temp_root .. "/cache/GTAGS" }
  local calls = 0
  pcall(vim.api.nvim_del_user_command, "GutentagsUpdate")
  vim.api.nvim_create_user_command("GutentagsUpdate", function()
    calls = calls + 1
  end, {})

  eq(true, adapter.update())
  eq(1, calls)
end)

test("runs one asynchronous global update per manual project", function()
  local root, source = manual_query_fixture("update-manual")
  edit(source)
  local old_system = vim.system
  local calls = {}
  local callback
  vim.system = function(cmd, opts, cb)
    calls[#calls + 1] = { cmd = cmd, opts = opts }
    callback = cb
    return { pid = 1234 }
  end

  local ok, err = xpcall(function()
    eq(true, adapter.update())
    eq(false, adapter.update())
    eq(1, #calls)
    eq({ "global", "-u" }, calls[1].cmd)
    eq(root, calls[1].opts.cwd)
    eq(root, calls[1].opts.env.GTAGSROOT)
    eq(root, calls[1].opts.env.GTAGSDBPATH)
    callback({ code = 0, stdout = "", stderr = "" })
    vim.wait(1000, function()
      return notifications[#notifications].message:find("更新完成", 1, true) ~= nil
    end)
  end, debug.traceback)
  vim.system = old_system
  if not ok then error(err) end
end)

test("does not build automatically inside a disabled project", function()
  local root = temp_root .. "/update-disabled"
  local source = root .. "/disabled.c"
  write(root .. "/.notags", {})
  write(source, { "int disabled_update_symbol;" })
  edit(source)

  eq(false, adapter.update())
  assert(notifications[#notifications].message:find("手动生成 GTAGS", 1, true))
end)

test("reports a failed manual global update", function()
  local _, source = manual_query_fixture("update-failure")
  edit(source)
  local old_system = vim.system
  local callback
  vim.system = function(_, _, cb)
    callback = cb
    return { pid = 5678 }
  end

  local ok, err = xpcall(function()
    eq(true, adapter.update())
    callback({ code = 2, stdout = "", stderr = "database locked" })
    assert(vim.wait(1000, function()
      local last = notifications[#notifications]
      return last and last.message:find("database locked", 1, true) ~= nil
    end))
  end, debug.traceback)
  vim.system = old_system
  if not ok then error(err) end
end)

test("checks gtags only for automatic updates", function()
  local root = temp_root .. "/update-missing-gtags"
  local source = root .. "/auto.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int auto_update_symbol;" })
  edit(source)
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = temp_root .. "/missing-cache/GTAGS" }
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    assert(notifications[#notifications].message:find("gtags", 1, true))
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("installs the leader-g update map", function()
  local mapping = vim.fn.maparg("<leader>gb", "n", false, true)
  assert(type(mapping) == "table" and mapping.desc, "missing map <leader>gb")
end)
```

- [ ] **Step 2: Run the test to verify RED**

Run the shared fast test command. Expected: failure `attempt to call field 'update' (a nil value)`.

- [ ] **Step 3: Implement update dispatch**

Add this public function before `M.setup()` in `lua/gtags_adapter.lua`:

```lua
function M.update()
  local context, context_error = current_context()
  if not context then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
  if context.mode == "automatic" then
    local missing = missing_tools({ "gtags" })
    if #missing > 0 then
      notify("缺少索引命令: gtags", vim.log.levels.ERROR)
      return false
    end
    if vim.fn.exists(":GutentagsUpdate") ~= 2 then
      notify("当前 buffer 没有 GutentagsUpdate 命令", vim.log.levels.ERROR)
      return false
    end
    vim.api.nvim_cmd({ cmd = "GutentagsUpdate" }, {})
    return true
  end
  if context.mode ~= "manual" then
    notify(context_error or "请先手动生成 GTAGS", vim.log.levels.WARN)
    return false
  end
  if vim.fn.executable("global") ~= 1 then
    notify("缺少索引更新命令: global", vim.log.levels.ERROR)
    return false
  end
  if manual_updates[context.root] then
    notify("当前手动索引已经在更新", vim.log.levels.WARN)
    return false
  end

  manual_updates[context.root] = true
  vim.system({ "global", "-u" }, {
    cwd = context.root,
    env = { GTAGSROOT = context.root, GTAGSDBPATH = context.root },
    text = true,
  }, function(result)
    manual_updates[context.root] = nil
    vim.schedule(function()
      if result.code == 0 then
        notify("手动 GTAGS 更新完成: " .. context.root)
      else
        local stderr = vim.trim(result.stderr or "")
        notify("手动 GTAGS 更新失败 (exit " .. result.code .. ")"
          .. (stderr ~= "" and (": " .. stderr) or ""), vim.log.levels.ERROR)
      end
    end)
  end)
  return true
end
```

At the end of `setup_keymaps()`, after the query-map loop, register the update map now that `M.update()` exists:

```lua
  vim.keymap.set("n", "<leader>gb", function()
    M.update()
  end, { silent = true, desc = "GTAGS: 更新索引" })
```

`current_context()` currently returns early for disabled/unconfigured contexts. Adjust it to return the classified context plus an error string for those two modes, and make `M.find()` reject them before querying. This lets `M.update()` issue the mode-specific manual-build message without duplicating filesystem classification:

```lua
  if context.mode == "disabled" then
    return context, context.root .. " 包含 .notags；请先手动生成 GTAGS"
  end
  if context.mode == "unconfigured" then
    return context, "找不到项目根；请在项目根创建 .root"
  end
```

Immediately after `current_context()` in `M.find()`, reject contexts without a database:

```lua
  if context.mode == "disabled" or context.mode == "unconfigured" then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
```

Immediately after `current_context()` in `M.update()`, handle disabled/unconfigured modes:

```lua
  if context.mode == "disabled" then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
  if context.mode == "unconfigured" then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
```

- [ ] **Step 4: Run the test to verify GREEN**

Run the shared fast test command. Expected: all tests pass, including duplicate manual-update suppression and scheduled success notification.

- [ ] **Step 5: Commit Task 3**

```bash
git add lua/gtags_adapter.lua tests/gtags_adapter_spec.lua
git commit -m "feat(gtags): update automatic and manual indexes"
```

## Task 4: Plugin Stack, Lockfile, And Real Integration

**Files:**
- Create: `tests/gtags_integration.lua`
- Modify: `lua/plugins/gtags.lua`
- Modify: `lua/plugins/telescope.lua`
- Modify: `lazy-lock.json`

- [ ] **Step 1: Write the failing full-stack integration test**

Create `tests/gtags_integration.lua`:

```lua
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
```

- [ ] **Step 2: Run the integration test to verify RED**

Install the current locked plugins in the isolated worktree app, then run the test:

```bash
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless "+Lazy! install" +qa
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless -l tests/gtags_integration.lua
```

Expected: failure because `:GscopeFind` does not exist and the current spec still loads `cscope_maps.nvim`.

- [ ] **Step 3: Replace the plugin spec**

Replace `lua/plugins/gtags.lua` with:

```lua
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
```

In `lua/plugins/telescope.lua`, replace the stale GTAGS dependency comment:

```lua
    -- telescope 本体保留，因为 aerial 大纲仍以它作为 picker。
    -- GTAGS 查询结果已经由 gtags_adapter 转交给 fzf-lua。
```

This replaces the existing lines that name `cscope_maps` as a retained Telescope consumer; do not change Telescope behavior.

- [ ] **Step 4: Install only missing plugins and inspect the lockfile**

Run:

```bash
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless "+Lazy! install" +qa
git diff -- lazy-lock.json
```

Expected lockfile changes: add `gutentags_plus` and `vim-gutentags`; remove `cscope_maps.nvim`; no unrelated plugin revisions. If lazy.nvim retains the stale cscope entry, remove only its JSON property while preserving valid JSON and every unrelated entry.

- [ ] **Step 5: Verify GREEN at unit and integration levels**

Run:

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless -l tests/gtags_integration.lua
rg -n '"(gutentags_plus|vim-gutentags)"' lazy-lock.json
rg -n 'cscope_maps' lua lazy-lock.json
```

Expected: both test suites pass; two new lock entries are printed; the final `rg` returns no matches.

- [ ] **Step 6: Commit Task 4**

```bash
git add lua/plugins/gtags.lua lua/plugins/telescope.lua lazy-lock.json tests/gtags_integration.lua
git commit -m "feat(gtags): integrate gutentags plugin stack"
```

## Task 5: Documentation And End-To-End Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the README structure entry and GTAGS section**

Change the structure comment for `gtags.lua` to:

```text
│       ├── gtags.lua       # Gutentags 自动/手动混合索引（结果走 fzf-lua）
```

Replace the existing “大型代码库符号跳转（gtags / cscope）” section with:

```markdown
### 大型代码库符号跳转（Gutentags / GNU GLOBAL）

本配置用三层协作完成跨文件符号查询：

- `vim-gutentags` 在后台生成并增量更新 GNU GLOBAL 数据库。
- `gutentags_plus` 为当前 buffer 选择正确数据库并执行 `gtags-cscope` 查询。
- `fzf-lua` 展示多条结果；单条结果直接跳转。

系统需要 `gtags`、`global`、`gtags-cscope`。配置使用 `native-pygments`，因此索引非 GNU GLOBAL 原生语言时还需要 Python 与 Pygments。由于 Neovim 0.9 已移除原生 cscope，这里使用带兼容补丁的 `skywind3000/vim-gutentags`，不再加载 `cscope_maps.nvim`。

索引模式按当前文件向上逐级判断，遇到第一个项目边界即停止：

1. 同一层有 `GTAGS`：手动模式，直接复用项目内数据库。
2. 同一层有 `.notags`：禁止自动索引，适合尚未手动建库的大仓库。
3. 同一层有 `.git`、`.root`、`.project` 等：自动模式，数据库保存到 `stdpath("cache")/gutentags`。

非版本库项目可在根目录创建空的 `.root`。新的大型仓库应先创建 `.notags`，再在根目录运行合适的建库命令：普通项目运行 `gtags`，Linux 内核运行 `make gtags`。已有项目内 `GTAGS` 时不需要保留 `.notags`。

查询键：

| 键位 | 功能 |
|---|---|
| `<leader>gd` | 定义 |
| `<leader>gs` | 符号/引用 |
| `<leader>gr` | 调用当前函数的位置 |
| `<leader>gt` | 文本 |
| `<leader>ge` | egrep |
| `<leader>gf` | 文件 |
| `<leader>gi` | include 当前文件的位置 |
| `<leader>gb` | 更新当前项目索引 |

首次自动建库或索引更新期间，查询会提示等待，避免读取尚未完成的数据库。自动模式的 `<leader>gb` 调用 `GutentagsUpdate`；手动模式异步运行 `global -u`。

排错：

- `:GutentagsToggleTrace` 开启日志，保存文件或执行 `:GutentagsUpdate` 后用 `:messages` 查看。
- 提示找不到项目根时，在正确目录创建 `.root`。
- 自动缓存损坏时，退出正在使用该项目的 Neovim，删除提示路径所在的缓存子目录，再重新打开文件建库。
- 手动数据库损坏时，不要让配置自动删除源码树文件；在项目根按项目要求重新运行 `gtags` 或 `make gtags`。
```

- [ ] **Step 2: Run the complete automated verification set**

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless -l tests/gtags_integration.lua
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless "+lua assert(vim.fn.exists(':GscopeFind') == 2)" "+lua assert(vim.fn.has('cscope') == 0)" +qa
git diff --check
```

Expected: both suites and full startup pass; `GscopeFind` exists without native cscope; `git diff --check` is silent.

- [ ] **Step 3: Verify the existing Linux kernel manual database**

Run only if `/home/ubuntu/Music/linux-6.12.92/GTAGS` still exists:

```bash
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless /home/ubuntu/Music/linux-6.12.92/mm/vmscan.c "+lua local line=vim.api.nvim_buf_get_lines(0,5961,5962,false)[1]; local col=assert(line:find('shrink_node',1,true))-1; vim.api.nvim_win_set_cursor(0,{5962,col}); assert(require('gtags_adapter').find('g')); assert(vim.b.gutentags_files.gtags_cscope == '/home/ubuntu/Music/linux-6.12.92/GTAGS')" +qa
```

Expected: exit 0 and no cache database selected for the kernel buffer.

- [ ] **Step 4: Confirm scope and dependency cleanup**

```bash
git status --short
git diff --stat HEAD~4..HEAD
rg -n 'cscope_maps|Cscope find|Cscope build' lua README.md lazy-lock.json
rg -n 'gutentags_plus|vim-gutentags' lua README.md lazy-lock.json
git -C /home/ubuntu/.config/nvim status --short
```

Expected: in the isolated feature worktree, only Task 5's README change remains uncommitted before its commit; no old cscope integration references remain, and all new stack references are intentional. The primary checkout status remains exactly the user's baseline changes: modified `lua/plugins/fzf-lua.lua`, modified `lua/plugins/markdown.lua`, untracked `markdown-preview.css`, and untracked `nvim.log`.

- [ ] **Step 5: Commit Task 5**

```bash
git add README.md
git commit -m "docs(gtags): document hybrid indexing workflow"
```

- [ ] **Step 6: Final branch verification**

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
XDG_CONFIG_HOME="$(dirname "$PWD")" NVIM_APPNAME="$(basename "$PWD")" nvim --headless -l tests/gtags_integration.lua
git status --short
git log --oneline --decorate -7
```

Expected: both tests pass, the isolated feature worktree is clean, the primary checkout's four baseline user changes remain untouched, and the branch shows five focused implementation commits after the design and plan commits.
