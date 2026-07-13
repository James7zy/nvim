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
local existing_hook_update
vim.g.existing_gutentags_hook_result = 1
_G.ExistingGutentagsHook = function(path)
  existing_hook_calls = existing_hook_calls + 1
  if existing_hook_update and path == existing_hook_update.path then
    vim.b.gutentags_root = existing_hook_update.root
    vim.b.gutentags_files = vim.deepcopy(existing_hook_update.files)
  end
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
  local hook_files = { gtags_cscope = root .. "/generated-GTAGS" }
  vim.b.gutentags_root = root
  vim.b.gutentags_files = hook_files

  eq(1, guard(source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(root, vim.b.gutentags_hybrid_root)
  eq({
    gutentags_files = hook_files,
    gutentags_root = root,
  }, {
    gutentags_files = vim.b.gutentags_files,
    gutentags_root = vim.b.gutentags_root,
  })
end)

test("clears a stale manual database when the project mode changes", function()
  local root = temp_root .. "/mode-transition"
  local source = root .. "/transition.c"
  local second_root = temp_root .. "/second-automatic"
  local second_source = second_root .. "/second.c"
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(second_root .. "/.git", "p")
  write(root .. "/GTAGS", { "manual database" })
  write(source, { "int transition_symbol;" })
  write(second_source, { "int second_symbol;" })
  edit(source)

  eq(0, guard(source))
  eq("manual", vim.b.gutentags_hybrid_mode)
  assert(vim.fn.delete(root .. "/GTAGS") == 0)
  eq(1, guard(source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(nil, vim.b.gutentags_root)
  eq(nil, vim.b.gutentags_files)

  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = root .. "/stale-GTAGS" }
  eq(1, guard(second_source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(second_root, vim.b.gutentags_hybrid_root)
  eq(nil, vim.b.gutentags_root)
  eq(nil, vim.b.gutentags_files)
end)

test("chains an existing Gutentags init hook", function()
  local root = temp_root .. "/existing-hook"
  local source = root .. "/hook.c"
  local second_root = temp_root .. "/existing-hook-second"
  local second_source = second_root .. "/hook-second.c"
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(second_root .. "/.git", "p")
  write(source, { "int hook_symbol;" })
  write(second_source, { "int hook_second_symbol;" })
  edit(source)
  local before = existing_hook_calls

  vim.g.existing_gutentags_hook_result = 0
  eq(0, guard(source))
  eq(before + 1, existing_hook_calls)

  vim.g.existing_gutentags_hook_result = false
  local false_result = guard(source)
  vim.g.existing_gutentags_hook_result = ""
  local empty_result = guard(source)

  local before_reload = existing_hook_calls
  local guard_before_reload = _G.NvimGutentagsHybridGuard
  package.loaded.gtags_adapter = nil
  require("gtags_adapter").setup()
  vim.g.existing_gutentags_hook_result = 1
  local reload_result = guard(source)

  eq({
    empty_result = 0,
    false_result = 0,
    guard_refreshed = true,
    reload_hook_calls = before_reload + 1,
    reload_result = 1,
  }, {
    empty_result = empty_result,
    false_result = false_result,
    guard_refreshed = guard_before_reload ~= _G.NvimGutentagsHybridGuard,
    reload_hook_calls = existing_hook_calls,
    reload_result = reload_result,
  })

  eq(root, vim.b.gutentags_hybrid_root)
  local destination_files = {
    gtags_cscope = second_root .. "/generated-GTAGS",
  }
  existing_hook_update = {
    files = destination_files,
    path = second_source,
    root = second_root,
  }
  local before_transition = existing_hook_calls
  eq(1, guard(second_source))
  eq(before_transition + 1, existing_hook_calls)
  eq(second_root, vim.b.gutentags_hybrid_root)
  eq({
    gutentags_files = destination_files,
    gutentags_root = second_root,
  }, {
    gutentags_files = vim.b.gutentags_files,
    gutentags_root = vim.b.gutentags_root,
  })
  existing_hook_update = nil
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
