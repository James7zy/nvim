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
local existing_hook_switch_to
vim.g.existing_gutentags_hook_result = 1
_G.ExistingGutentagsHook = function(path)
  existing_hook_calls = existing_hook_calls + 1
  if existing_hook_update and path == existing_hook_update.path then
    vim.b.gutentags_root = existing_hook_update.root
    vim.b.gutentags_files = vim.deepcopy(existing_hook_update.files)
  end
  if existing_hook_switch_to then
    vim.api.nvim_set_current_buf(existing_hook_switch_to)
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

local function wait_for_trusted_target(bufnr, target)
  assert(vim.wait(1000, function()
    local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
    return type(record) == "table"
      and type(record.trusted) == "table"
      and record.trusted.target == target
  end, 10), "automatic metadata was not observed after setup")
end

write(temp_root .. "/autoload/gutentags.vim", {
  "function! gutentags#inprogress() abort",
  "  return get(g:, 'test_gutentags_jobs', [])",
  "endfunction",
  "function! gutentags#find_job_index_by_tags_file(module, target) abort",
  "  return index(get(g:, 'test_gutentags_job_targets', []), a:target)",
  "endfunction",
})
vim.opt.runtimepath:prepend(temp_root)
vim.g.test_gutentags_jobs = {}
vim.g.test_gutentags_job_targets = {}

local function install_write_hooks(bufnr, user_group_name)
  local calls = { gutentags = 0, user = 0 }
  local gutentags_group = vim.api.nvim_create_augroup(
    "gutentags_buffer_" .. bufnr, { clear = true }
  )
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = gutentags_group,
    buffer = bufnr,
    callback = function() calls.gutentags = calls.gutentags + 1 end,
  })
  local user_group = vim.api.nvim_create_augroup(user_group_name, { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = user_group,
    buffer = bufnr,
    callback = function() calls.user = calls.user + 1 end,
  })
  return calls
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

test("does not create first trust during a nonautomatic transition", function()
  local root = temp_root .. "/untrusted-transition"
  local source = root .. "/transition.c"
  local target = temp_root .. "/untrusted-cache/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int untrusted_transition_symbol;" })
  edit(source)

  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_hybrid_mode = "automatic"
  vim.b.gutentags_hybrid_root = root
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = target }
  _G.NvimGutentagsHybridState.automatic_transitions[bufnr] = nil
  write(root .. "/GTAGS", { "manual database" })

  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(nil, _G.NvimGutentagsHybridState.automatic_transitions[bufnr])
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("observes first trust after stable automatic setup", function()
  local root = temp_root .. "/stable-automatic-observer"
  local source = root .. "/stable.c"
  local target = temp_root .. "/stable-observer-cache/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int stable_observer_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = target }
  eq(nil, _G.NvimGutentagsHybridState.automatic_transitions[bufnr])
  assert(vim.wait(1000, function()
    local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
    return type(record) == "table"
      and type(record.trusted) == "table"
      and record.trusted.target == target
  end, 10), "stable automatic setup did not establish trust")
end)

test("blocks trust when the boundary changes before observation", function()
  local root = temp_root .. "/changed-observer-boundary"
  local source = root .. "/changed.c"
  local target = temp_root .. "/changed-observer-cache/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int changed_observer_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = target }
  write(root .. "/GTAGS", { "manual database" })
  vim.wait(100)
  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(true, type(record) == "table" and record.invalid_setup == true)
  eq(nil, record.trusted)

  assert(vim.fn.delete(root .. "/GTAGS") == 0)
  eq(1, guard(source))
  vim.wait(100)
  record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(true, type(record) == "table" and record.invalid_setup == true)
  eq(nil, record.trusted)

  write(root .. "/GTAGS", { "manual database" })
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("blocks overlapping same-root first-trust observers", function()
  local root = temp_root .. "/overlapping-observers"
  local source = root .. "/overlap.c"
  local c1 = temp_root .. "/overlap-cache-1/GTAGS"
  local c2 = temp_root .. "/overlap-cache-2/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int overlapping_observer_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  vim.g.test_gutentags_job_targets = { c1 }
  vim.b.gutentags_files = { gtags_cscope = c2 }
  eq(1, guard(source))
  vim.wait(100)

  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(true, type(record) == "table" and record.invalid_setup == true)
  eq(nil, record.trusted)

  write(root .. "/GTAGS", { "manual database" })
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    vim.g.test_gutentags_job_targets = {}
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(nil, record.trusted)
  end, debug.traceback)
  vim.env.PATH = old_path
  vim.g.test_gutentags_job_targets = {}
  if not ok then error(err) end
end)

test("observes a later target after first trust completes", function()
  local root = temp_root .. "/serialized-observers"
  local source = root .. "/serialized.c"
  local c1 = temp_root .. "/serialized-cache-1/GTAGS"
  local c2 = temp_root .. "/serialized-cache-2/GTAGS"
  local c3 = temp_root .. "/serialized-cache-3/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int serialized_observer_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)

  vim.b.gutentags_files = { gtags_cscope = c2 }
  eq(1, guard(source))
  assert(vim.wait(1000, function()
    local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
    return type(record) == "table"
      and type(record.candidate) == "table"
      and record.candidate.target == c2
  end, 10), "serialized observer did not retain the later candidate")
  vim.b.gutentags_files = { gtags_cscope = c3 }
  eq(1, guard(source))
  assert(vim.wait(1000, function()
    local current = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
    return type(current) == "table"
      and type(current.candidate) == "table"
      and current.candidate.target == c3
  end, 10), "serialized observer did not retain the final candidate")
  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(c1, record.trusted.target)
  eq({ [c1] = true, [c2] = true, [c3] = true }, record.targets)

  write(root .. "/GTAGS", { "manual database" })
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    vim.g.test_gutentags_job_targets = {}
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(false, adapter.update())
    assert(vim.wait(1000, function()
      return vim.b[bufnr].gutentags_hybrid_mode == "manual"
    end, 10))
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("blocks overlapping target observers after first trust", function()
  local root = temp_root .. "/overlapping-trusted-observers"
  local source = root .. "/trusted-overlap.c"
  local c1 = temp_root .. "/trusted-overlap-cache-1/GTAGS"
  local c2 = temp_root .. "/trusted-overlap-cache-2/GTAGS"
  local c3 = temp_root .. "/trusted-overlap-cache-3/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int trusted_overlap_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)

  vim.g.test_gutentags_job_targets = { c2 }
  vim.b.gutentags_files = { gtags_cscope = c2 }
  eq(1, guard(source))
  vim.b.gutentags_files = { gtags_cscope = c3 }
  eq(1, guard(source))
  vim.wait(100)

  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(true, record.observer_conflict)
  eq(c1, record.trusted.target)
  eq({ [c1] = true }, record.targets)

  write(root .. "/GTAGS", { "manual database" })
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    vim.g.test_gutentags_job_targets = {}
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(true, record.observer_conflict)
  end, debug.traceback)
  vim.env.PATH = old_path
  vim.g.test_gutentags_job_targets = {}
  if not ok then error(err) end
end)

test("preserves pending observer conflicts across reload and wipeout", function()
  local root = temp_root .. "/reload-pending-observer"
  local source = root .. "/reload.c"
  local c1 = temp_root .. "/reload-pending-cache-1/GTAGS"
  local c2 = temp_root .. "/reload-pending-cache-2/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int reload_pending_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  local shared_state = _G.NvimGutentagsHybridState
  assert(type(shared_state.automatic_observers) == "table")
  eq(true, shared_state.automatic_observers[bufnr].pending)

  package.loaded.gtags_adapter = nil
  require("gtags_adapter").setup()
  eq(true, shared_state.automatic_observers[bufnr].pending)
  vim.b.gutentags_files = { gtags_cscope = c2 }
  eq(1, guard(source))
  vim.wait(100)
  local record = shared_state.automatic_transitions[bufnr]
  eq(true, type(record) == "table" and record.invalid_setup == true)
  eq(nil, record.trusted)

  package.loaded.gtags_adapter = nil
  require("gtags_adapter").setup()
  eq(true, shared_state.automatic_transitions[bufnr].invalid_setup)
  vim.api.nvim_buf_delete(bufnr, { force = true })
  eq(nil, shared_state.automatic_transitions[bufnr])
  eq(nil, shared_state.automatic_observers[bufnr])
end)

test("does not create trust from current context while observer is pending", function()
  local root = temp_root .. "/pending-current-context"
  local source = root .. "/pending.c"
  local target = temp_root .. "/pending-current-cache/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int pending_current_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = target }
  eq(false, adapter.update())
  eq(nil, _G.NvimGutentagsHybridState.automatic_transitions[bufnr])
  wait_for_trusted_target(bufnr, target)
end)

test("defers trusted current-context refresh to the pending observer", function()
  local root = temp_root .. "/trusted-pending-current"
  local source = root .. "/trusted-pending.c"
  local c1 = temp_root .. "/trusted-pending-cache-1/GTAGS"
  local c2 = temp_root .. "/trusted-pending-cache-2/GTAGS"
  local c3 = temp_root .. "/trusted-pending-cache-3/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int trusted_pending_current_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)

  vim.b.gutentags_files = { gtags_cscope = c2 }
  eq(1, guard(source))
  eq(false, adapter.update())
  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(c1, record.trusted.target)
  eq(nil, record.candidate)
  eq({ [c1] = true }, record.targets)

  assert(vim.wait(1000, function()
    return type(record.candidate) == "table" and record.candidate.target == c2
  end, 10), "pending observer did not record C2")
  eq({ [c1] = true, [c2] = true }, record.targets)

  vim.b.gutentags_files = { gtags_cscope = c3 }
  eq(false, adapter.update())
  eq(c3, record.candidate.target)
  eq({ [c1] = true, [c2] = true, [c3] = true }, record.targets)
end)

test("blocks malformed observer state during current-context refresh", function()
  local root = temp_root .. "/malformed-current-observer"
  local source = root .. "/malformed-current.c"
  local c1 = temp_root .. "/malformed-current-cache-1/GTAGS"
  local c2 = temp_root .. "/malformed-current-cache-2/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int malformed_current_observer_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)
  local state = _G.NvimGutentagsHybridState
  local record = state.automatic_transitions[bufnr]
  state.automatic_observers[bufnr] = "malformed"
  vim.b.gutentags_files = { gtags_cscope = c2 }

  eq(false, adapter.update())
  eq(true, record.observer_conflict)
  eq(c1, record.trusted.target)
  eq(nil, record.candidate)
  eq({ [c1] = true }, record.targets)
  state.automatic_observers[bufnr] = nil
end)

test("does not observe a pending target during nonautomatic transition", function()
  local root = temp_root .. "/pending-transition-observer"
  local source = root .. "/pending-transition.c"
  local c1 = temp_root .. "/pending-transition-cache-1/GTAGS"
  local c2 = temp_root .. "/pending-transition-cache-2/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int pending_transition_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)
  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]

  vim.b.gutentags_files = { gtags_cscope = c2 }
  eq(1, guard(source))
  write(root .. "/GTAGS", { "manual database" })
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    eq(c1, record.trusted.target)
    eq(nil, record.candidate)
    eq({ [c1] = true }, record.targets)
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(c1, record.trusted.target)
    eq(nil, record.candidate)
    eq({ [c1] = true }, record.targets)
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("blocks malformed observer during nonautomatic transition", function()
  local root = temp_root .. "/malformed-transition-observer"
  local source = root .. "/malformed-transition.c"
  local c1 = temp_root .. "/malformed-transition-cache-1/GTAGS"
  local c2 = temp_root .. "/malformed-transition-cache-2/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int malformed_transition_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)
  local state = _G.NvimGutentagsHybridState
  local record = state.automatic_transitions[bufnr]
  state.automatic_observers[bufnr] = "malformed"
  vim.b.gutentags_files = { gtags_cscope = c2 }
  write(root .. "/GTAGS", { "manual database" })

  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    eq(true, record.observer_conflict)
    eq(nil, record.candidate)
    eq({ [c1] = true }, record.targets)
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(true, record.observer_conflict)
    eq(nil, record.candidate)
    eq({ [c1] = true }, record.targets)
  end, debug.traceback)
  vim.env.PATH = old_path
  state.automatic_observers[bufnr] = nil
  if not ok then error(err) end
end)

test("rechecks observer state in scheduled transition callback", function()
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    for _, kind in ipairs({ "pending", "malformed" }) do
      local root = temp_root .. "/callback-observer-" .. kind
      local source = root .. "/callback.c"
      local c1 = temp_root .. "/callback-cache-1-" .. kind .. "/GTAGS"
      local c2 = temp_root .. "/callback-cache-2-" .. kind .. "/GTAGS"
      vim.fn.mkdir(root .. "/.git", "p")
      write(source, { "int callback_observer_symbol;" })
      edit(source)

      eq(1, guard(source))
      local bufnr = vim.api.nvim_get_current_buf()
      vim.b.gutentags_root = root
      vim.b.gutentags_files = { gtags_cscope = c1 }
      wait_for_trusted_target(bufnr, c1)
      local state = _G.NvimGutentagsHybridState
      local record = state.automatic_transitions[bufnr]
      local observer = state.automatic_observers[bufnr]
      write(root .. "/GTAGS", { "manual database" })
      eq(false, adapter.update())

      vim.b.gutentags_files = { gtags_cscope = c2 }
      if kind == "pending" then
        state.automatic_observers[bufnr] = {
          generation = observer.generation + 1,
          pending = true,
        }
      else
        state.automatic_observers[bufnr] = "malformed"
      end
      vim.wait(100)
      eq("automatic", vim.b.gutentags_hybrid_mode)
      eq(c1, record.trusted.target)
      eq(nil, record.candidate)
      eq({ [c1] = true }, record.targets)
      if kind == "malformed" then
        eq(true, record.observer_conflict)
      end
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("blocks foreign-root metadata in scheduled observation", function()
  local root = temp_root .. "/foreign-root-observer"
  local foreign_root = temp_root .. "/foreign-root-observer-other"
  local source = root .. "/foreign.c"
  local c1 = temp_root .. "/foreign-root-cache-1/GTAGS"
  local c2 = temp_root .. "/foreign-root-cache-2/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int foreign_root_observer_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = foreign_root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  vim.g.test_gutentags_job_targets = { c1 }
  vim.wait(100)
  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(true, type(record) == "table" and record.invalid_setup == true)
  eq(nil, record.trusted)

  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c2 }
  eq(1, guard(source))
  vim.wait(100)
  record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  eq(true, type(record) == "table" and record.invalid_setup == true)
  eq(nil, record.trusted)
  vim.g.test_gutentags_job_targets = {}
end)

test("blocks foreign-root metadata in current-context refresh", function()
  local root = temp_root .. "/foreign-root-current"
  local foreign_root = temp_root .. "/foreign-root-current-other"
  local source = root .. "/foreign-current.c"
  local c1 = temp_root .. "/foreign-current-cache-1/GTAGS"
  local c2 = temp_root .. "/foreign-current-cache-2/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int foreign_root_current_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)
  local record = _G.NvimGutentagsHybridState.automatic_transitions[bufnr]
  vim.b.gutentags_root = foreign_root
  vim.b.gutentags_files = { gtags_cscope = c2 }

  eq(false, adapter.update())
  eq(true, record.observer_conflict)
  eq(c1, record.trusted.target)
  eq(nil, record.candidate)
  eq({ [c1] = true }, record.targets)
end)

test("defers a live manual transition until Gutentags work is quiescent", function()
  local root = temp_root .. "/live-manual-transition"
  local source = root .. "/transition.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int transition_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  local automatic_files = { gtags_cscope = temp_root .. "/cache/GTAGS" }
  vim.b.gutentags_files = automatic_files
  wait_for_trusted_target(bufnr, automatic_files.gtags_cscope)
  local writes = install_write_hooks(bufnr, "gtags_adapter_user_" .. bufnr)

  write(root .. "/GTAGS", { "manual database" })
  local old_path = vim.env.PATH
  local old_notify = vim.notify
  local notifications = {}
  local completion_result
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    vim.notify = function(message)
      notifications[#notifications + 1] = tostring(message)
    end
    vim.g.test_gutentags_jobs = { "gtags_cscope" }

    eq(false, adapter.update())
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(root, vim.b.gutentags_root)
    eq(automatic_files, vim.b.gutentags_files)
    assert(notifications[#notifications]:find("try again shortly", 1, true))
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
    eq({ gutentags = 1, user = 1 }, writes)

    vim.g.test_gutentags_jobs = {}
    local completion_group = vim.api.nvim_create_augroup(
      "gtags_adapter_completion_gap", { clear = true }
    )
    vim.api.nvim_create_autocmd("User", {
      group = completion_group,
      pattern = "GutentagsUpdated",
      callback = function() completion_result = adapter.update() end,
    })
    vim.api.nvim_create_autocmd("User", {
      group = completion_group,
      pattern = "GutentagsUpdated",
      callback = function()
        vim.g.test_gutentags_jobs = { "gtags_cscope" }
      end,
    })
    vim.api.nvim_exec_autocmds("User", { pattern = "GutentagsUpdated" })
    eq(false, completion_result)
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(automatic_files, vim.b.gutentags_files)

    vim.g.test_gutentags_jobs = {}
    eq(false, adapter.update())
    eq("automatic", vim.b.gutentags_hybrid_mode)
    assert(vim.wait(1000, function()
      return vim.b[bufnr].gutentags_hybrid_mode == "manual"
    end, 10))
    eq("manual", vim.b.gutentags_hybrid_mode)
    eq(root .. "/GTAGS", vim.b.gutentags_files.gtags_cscope)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
    eq({ gutentags = 1, user = 2 }, writes)
  end, debug.traceback)
  vim.g.test_gutentags_jobs = {}
  vim.env.PATH = old_path
  vim.notify = old_notify
  pcall(vim.api.nvim_del_augroup_by_name, "gtags_adapter_completion_gap")
  if not ok then error(err) end
end)

test("defers rescan until automatic metadata is restored and quiescent", function()
  local root = temp_root .. "/rescan-transition"
  local source = root .. "/rescan.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int rescan_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  local automatic_files = {
    gtags_cscope = temp_root .. "/rescan-cache/GTAGS",
  }
  vim.b.gutentags_root = root
  vim.b.gutentags_files = automatic_files
  wait_for_trusted_target(bufnr, automatic_files.gtags_cscope)
  local writes = install_write_hooks(
    bufnr, "gtags_adapter_rescan_user_" .. bufnr
  )
  write(root .. "/GTAGS", { "manual database" })

  vim.g.test_gutentags_jobs = { "gtags_cscope" }
  vim.b.gutentags_files = nil
  eq(1, guard(source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(root, vim.b.gutentags_root)
  eq(nil, vim.b.gutentags_files)
  vim.b.gutentags_files = automatic_files
  vim.wait(100)
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(automatic_files, vim.b.gutentags_files)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  eq({ gutentags = 1, user = 1 }, writes)

  vim.g.test_gutentags_jobs = {}
  vim.b.gutentags_files = nil
  eq(1, guard(source))
  local wrong_files = {
    gtags_cscope = temp_root .. "/wrong-rescan-cache/GTAGS",
  }
  vim.b.gutentags_files = wrong_files
  vim.wait(100)
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(wrong_files, vim.b.gutentags_files)
  vim.b.gutentags_files = automatic_files
  vim.wait(20)
  eq("automatic", vim.b.gutentags_hybrid_mode)

  vim.b.gutentags_files = nil
  eq(1, guard(source))
  vim.b.gutentags_files = automatic_files
  assert(vim.wait(1000, function()
    return vim.b[bufnr].gutentags_hybrid_mode == "manual"
  end, 10))
  eq(root .. "/GTAGS", vim.b.gutentags_files.gtags_cscope)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  eq({ gutentags = 1, user = 2 }, writes)
  vim.g.test_gutentags_jobs = {}
end)

test("retains every migrated automatic target until exact adoption", function()
  local root = temp_root .. "/multi-target-transition"
  local source = root .. "/migration.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int migration_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  local c1 = temp_root .. "/migration-cache-1/GTAGS"
  local c2 = temp_root .. "/migration-cache-2/GTAGS"
  local c3 = temp_root .. "/migration-cache-3/GTAGS"
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = c1 }
  wait_for_trusted_target(bufnr, c1)
  local writes = install_write_hooks(
    bufnr, "gtags_adapter_migration_user_" .. bufnr
  )
  write(root .. "/GTAGS", { "manual database" })

  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    vim.g.test_gutentags_jobs = {}
    vim.g.test_gutentags_job_targets = { c1 }
    vim.b.gutentags_files = { gtags_cscope = c2 }
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(c2, vim.b.gutentags_files.gtags_cscope)

    vim.g.test_gutentags_job_targets = { c1, c2 }
    vim.b.gutentags_files = { gtags_cscope = c3 }
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(c3, vim.b.gutentags_files.gtags_cscope)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
    eq({ gutentags = 1, user = 1 }, writes)

    vim.g.test_gutentags_job_targets = {}
    eq(false, adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(c3, vim.b.gutentags_files.gtags_cscope)

    eq(false, adapter.update())
    assert(vim.wait(1000, function()
      return vim.b[bufnr].gutentags_hybrid_mode == "manual"
    end, 10))
    eq(root .. "/GTAGS", vim.b.gutentags_files.gtags_cscope)
    vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
    eq({ gutentags = 1, user = 2 }, writes)
  end, debug.traceback)
  vim.env.PATH = old_path
  vim.g.test_gutentags_jobs = {}
  vim.g.test_gutentags_job_targets = {}
  if not ok then error(err) end
end)

test("restores trusted automatic metadata during a notags rescan", function()
  local root = temp_root .. "/notags-rescan"
  local source = root .. "/notags.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int notags_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  local cache_files = {
    gtags_cscope = temp_root .. "/notags-rescan-cache/GTAGS",
  }
  vim.b.gutentags_root = root
  vim.b.gutentags_files = cache_files
  wait_for_trusted_target(bufnr, cache_files.gtags_cscope)
  local writes = install_write_hooks(
    bufnr, "gtags_adapter_notags_user_" .. bufnr
  )
  write(root .. "/.notags", {})

  vim.g.test_gutentags_job_targets = { cache_files.gtags_cscope }
  vim.b.gutentags_files = nil
  eq(1, guard(source))
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(root, vim.b.gutentags_root)
  eq(cache_files, vim.b.gutentags_files)
  vim.wait(100)
  eq("automatic", vim.b.gutentags_hybrid_mode)
  eq(cache_files, vim.b.gutentags_files)

  vim.g.test_gutentags_job_targets = {}
  eq(false, adapter.update())
  assert(vim.wait(1000, function()
    return vim.b[bufnr].gutentags_hybrid_mode == "disabled"
  end, 10))
  eq(nil, vim.b.gutentags_root)
  eq(nil, vim.b.gutentags_files)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = bufnr })
  eq({ gutentags = 0, user = 1 }, writes)
  vim.g.test_gutentags_job_targets = {}
end)

test("keeps hybrid ownership when a chained hook switches buffers", function()
  local target_root = temp_root .. "/hook-switch-target"
  local target_source = target_root .. "/target.c"
  local other_root = temp_root .. "/hook-switch-other"
  local other_source = other_root .. "/other.c"
  vim.fn.mkdir(target_root .. "/.git", "p")
  vim.fn.mkdir(other_root .. "/.git", "p")
  write(target_source, { "int target_symbol;" })
  write(other_source, { "int other_symbol;" })

  edit(target_source)
  eq(1, guard(target_source))
  local target_buf = vim.api.nvim_get_current_buf()
  local target_files = { gtags_cscope = temp_root .. "/target-cache/GTAGS" }
  vim.b.gutentags_root = target_root
  vim.b.gutentags_files = target_files
  wait_for_trusted_target(target_buf, target_files.gtags_cscope)
  local target_writes = install_write_hooks(
    target_buf, "gtags_adapter_target_user_" .. target_buf
  )

  edit(other_source)
  eq(1, guard(other_source))
  local other_buf = vim.api.nvim_get_current_buf()
  local other_files = { gtags_cscope = temp_root .. "/other-cache/GTAGS" }
  vim.b.gutentags_root = other_root
  vim.b.gutentags_files = other_files
  local other_writes = install_write_hooks(
    other_buf, "gtags_adapter_other_user_" .. other_buf
  )

  write(target_root .. "/GTAGS", { "manual database" })
  vim.api.nvim_set_current_buf(target_buf)
  existing_hook_switch_to = other_buf
  local ok, result = pcall(guard, target_source)
  existing_hook_switch_to = nil
  assert(ok, result)
  eq(1, result)
  eq("automatic", vim.b[target_buf].gutentags_hybrid_mode)
  eq(target_files, vim.b[target_buf].gutentags_files)
  eq("automatic", vim.b[other_buf].gutentags_hybrid_mode)
  eq(other_files, vim.b[other_buf].gutentags_files)
  assert(vim.wait(1000, function()
    return vim.b[target_buf].gutentags_hybrid_mode == "manual"
  end, 10))
  eq("manual", vim.b[target_buf].gutentags_hybrid_mode)
  eq(target_root, vim.b[target_buf].gutentags_root)
  eq(target_root .. "/GTAGS",
    vim.b[target_buf].gutentags_files.gtags_cscope)
  eq("automatic", vim.b[other_buf].gutentags_hybrid_mode)
  eq(other_root, vim.b[other_buf].gutentags_root)
  eq(other_files, vim.b[other_buf].gutentags_files)

  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = target_buf })
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = other_buf })
  eq({ gutentags = 0, user = 1 }, target_writes)
  eq({ gutentags = 1, user = 1 }, other_writes)
end)

test("chains an existing Gutentags init hook", function()
  local root = temp_root .. "/existing-hook"
  local source = root .. "/hook.c"
  local second_root = temp_root .. "/existing-hook-second"
  local second_source = second_root .. "/hook-second.c"
  local third_root = temp_root .. "/existing-hook-third"
  local third_source = third_root .. "/hook-third.c"
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(second_root .. "/.git", "p")
  vim.fn.mkdir(third_root .. "/.git", "p")
  write(source, { "int hook_symbol;" })
  write(second_source, { "int hook_second_symbol;" })
  write(third_source, { "int hook_third_symbol;" })
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
    ctags = second_root .. "/tags",
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

  local mixed_files = {
    ctags = third_root .. "/tags",
    gtags_cscope = destination_files.gtags_cscope,
  }
  existing_hook_update = {
    files = mixed_files,
    path = third_source,
    root = third_root,
  }
  local before_mixed_transition = existing_hook_calls
  eq(1, guard(third_source))
  eq(before_mixed_transition + 1, existing_hook_calls)
  eq(third_root, vim.b.gutentags_hybrid_root)
  eq(third_root, vim.b.gutentags_root)
  eq({ ctags = mixed_files.ctags }, vim.b.gutentags_files)
  existing_hook_update = nil
end)

local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = tostring(message), level = level }
end

local query_items = {}
local last_query
local query_calls = 0
local query_shell_error = 0

local function set_shell_error(code)
  vim.fn.system({ "/bin/sh", "-c", "exit " .. tostring(code) })
end

vim.api.nvim_create_user_command("GscopeFind", function(opts)
  query_calls = query_calls + 1
  last_query = { args = opts.fargs, bang = opts.bang }
  vim.fn.setqflist({}, "r", { title = "test GscopeFind", items = query_items })
  set_shell_error(query_shell_error)
end, { nargs = "+", bang = true })

local fzf_calls = 0
package.loaded["fzf-lua"] = {
  quickfix = function(opts)
    fzf_calls = fzf_calls + 1
    eq(true, opts.valid_only)
  end,
}

local function with_fzf_stub(stub, fn)
  local original = package.loaded["fzf-lua"]
  package.loaded["fzf-lua"] = stub
  local ok, err = xpcall(fn, debug.traceback)
  package.loaded["fzf-lua"] = original
  if not ok then error(err) end
end

local function manual_query_fixture(name)
  local root = temp_root .. "/query-" .. name
  local source = root .. "/source.c"
  write(root .. "/GTAGS", { "test database" })
  write(source, { "int query_symbol(void) { return 1; }" })
  edit(source)
  assert(vim.fn.search("query_symbol") > 0)
  return root, source
end

test("reports an empty query without opening fzf", function()
  manual_query_fixture("empty")
  query_items = { { text = '[cscope g: definition of "query_symbol"]' } }
  local before_fzf = fzf_calls

  eq(false, adapter.find("g"))
  eq(before_fzf, fzf_calls)
  assert(notifications[#notifications].message:find("No matches", 1, true))
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
  local retained = vim.fn.getqflist()
  eq(2, #retained)
  for _, item in ipairs(retained) do
    assert(item.valid == 1 and item.bufnr > 0 and item.lnum > 0,
      "quickfix retained a non-location item")
  end
end)

test("surfaces a line-zero database error instead of opening fzf", function()
  manual_query_fixture("corrupt")
  query_items = {
    { text = '[cscope g: definition of "query_symbol"]' },
    { text = "GTAGS corrupted", lnum = 0 },
  }
  local before_fzf = fzf_calls

  eq(false, adapter.find("g"))
  eq(before_fzf, fzf_calls)
  assert(notifications[#notifications].message:find("GTAGS corrupted", 1, true))
end)

test("reports a nonzero query exit status as a backend failure", function()
  local root = manual_query_fixture("backend-failure")
  query_items = { { text = '[cscope g: definition of "query_symbol"]' } }
  local before_calls = query_calls
  local ok, err = xpcall(function()
    query_shell_error = 7
    eq(false, adapter.find("g"))
    eq(before_calls + 1, query_calls)
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    assert(notification.message:find("query failed", 1, true))
    assert(notification.message:find("7", 1, true))
    assert(notification.message:find(root .. "/GTAGS", 1, true))
    eq(nil, notification.message:find("No matches", 1, true))
  end, debug.traceback)
  query_shell_error = 0
  set_shell_error(0)
  if not ok then error(err) end
end)

test("rejects invalid query kinds without invoking GscopeFind", function()
  manual_query_fixture("invalid-kind")
  query_items = { { text = '[cscope x: invalid "query_symbol"]' } }
  local before_calls = query_calls
  local before_notifications = #notifications

  eq(false, adapter.find(nil))
  eq(false, adapter.find("x"))
  eq(before_calls, query_calls)
  eq(before_notifications + 2, #notifications)
  for index = before_notifications + 1, #notifications do
    eq(vim.log.levels.ERROR, notifications[index].level)
    assert(notifications[index].message:find("query type", 1, true))
  end
end)

test("reports fzf-lua without quickfix as unavailable", function()
  local root = manual_query_fixture("fzf-missing-quickfix")
  local first = root .. "/first.c"
  local second = root .. "/second.c"
  write(first, { "int query_symbol;" })
  write(second, { "int query_symbol;" })
  query_items = {
    { text = '[cscope s: symbol "query_symbol"]' },
    { filename = first, lnum = 1, col = 1, text = "first" },
    { filename = second, lnum = 1, col = 1, text = "second" },
  }

  with_fzf_stub({}, function()
    local call_ok, result = pcall(adapter.find, "s")
    eq(true, call_ok)
    eq(false, result)
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    assert(notification.message:find("fzf-lua", 1, true))
  end)
end)

test("reports a synchronous fzf-lua quickfix failure", function()
  local root = manual_query_fixture("fzf-throws")
  local first = root .. "/first.c"
  local second = root .. "/second.c"
  write(first, { "int query_symbol;" })
  write(second, { "int query_symbol;" })
  query_items = {
    { text = '[cscope s: symbol "query_symbol"]' },
    { filename = first, lnum = 1, col = 1, text = "first" },
    { filename = second, lnum = 1, col = 1, text = "second" },
  }

  with_fzf_stub({
    quickfix = function()
      error("test fzf failure")
    end,
  }, function()
    local call_ok, result = pcall(adapter.find, "s")
    eq(true, call_ok)
    eq(false, result)
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    assert(notification.message:find("fzf-lua", 1, true))
  end)
end)

test("preserves a manual query lock across adapter reloads", function()
  local root = manual_query_fixture("manual-reload-lock")
  query_items = { { text = '[cscope g: definition of "query_symbol"]' } }
  local shared_state = _G.NvimGutentagsHybridState
  shared_state.manual_updates = shared_state.manual_updates or {}
  local before_calls = query_calls
  local ok, err = xpcall(function()
    shared_state.manual_updates[root] = true
    package.loaded.gtags_adapter = nil
    local reloaded_adapter = require("gtags_adapter")
    reloaded_adapter.setup()

    eq(false, reloaded_adapter.find("g"))
    eq(before_calls, query_calls)
    assert(notifications[#notifications].message:find(
      "manual index is being updated", 1, true))
  end, debug.traceback)
  shared_state.manual_updates[root] = nil
  if not ok then error(err) end
end)

test("migrates legacy automatic metadata on reload", function()
  local root = temp_root .. "/legacy-automatic-state"
  local source = root .. "/legacy.c"
  local target = temp_root .. "/legacy-cache/GTAGS"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int legacy_state_symbol;" })
  edit(source)

  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local shared_state = _G.NvimGutentagsHybridState
  local previous_legacy = shared_state.automatic_metadata
  local previous_record = shared_state.automatic_transitions[bufnr]
  local ok, err = xpcall(function()
    shared_state.automatic_metadata = {
      [bufnr] = {
        files = { gtags_cscope = target },
        hybrid_root = root,
        path = path,
        root = root,
        target = target,
      },
    }
    shared_state.automatic_transitions[bufnr] = nil
    package.loaded.gtags_adapter = nil
    require("gtags_adapter").setup()

    eq(nil, shared_state.automatic_metadata)
    eq({
      hybrid_root = root,
      path = path,
      targets = { [target] = true },
      trusted = {
        files = { gtags_cscope = target },
        root = root,
        target = target,
      },
    }, shared_state.automatic_transitions[bufnr])
  end, debug.traceback)
  shared_state.automatic_metadata = previous_legacy
  shared_state.automatic_transitions[bufnr] = previous_record
  if not ok then error(err) end
end)

test("cleans automatic transition state on wipeout after reload", function()
  local root = temp_root .. "/wipeout-state"
  local source = root .. "/wipeout.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int wipeout_symbol;" })
  edit(source)

  eq(1, guard(source))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.b.gutentags_root = root
  vim.b.gutentags_files = {
    gtags_cscope = temp_root .. "/wipeout-cache/GTAGS",
  }
  wait_for_trusted_target(bufnr, vim.b.gutentags_files.gtags_cscope)
  local shared_state = _G.NvimGutentagsHybridState
  assert(type(shared_state.automatic_transitions) == "table")
  assert(type(shared_state.automatic_transitions[bufnr]) == "table")

  package.loaded.gtags_adapter = nil
  require("gtags_adapter").setup()
  assert(type(shared_state.automatic_transitions[bufnr]) == "table")
  vim.api.nvim_buf_delete(bufnr, { force = true })
  eq(nil, shared_state.automatic_transitions[bufnr])
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
  assert(notifications[#notifications].message:find("building or updating the index", 1, true))
  vim.g.test_gutentags_jobs = {}
end)

test("rejects automatic queries until Gutentags prepares a database", function()
  local root = temp_root .. "/query-automatic-unprepared"
  local source = root .. "/source.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int query_symbol(void) { return 1; }" })
  edit(source)
  local before_calls = query_calls

  eq(false, adapter.find("g"))
  eq(before_calls, query_calls)
  local notification = notifications[#notifications]
  eq(vim.log.levels.WARN, notification.level)
  eq("Gutentags has not prepared the current project's database yet", notification.message)
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
  local expected_maps = {
    d = "GTAGS: Definition",
    s = "GTAGS: Symbol/References",
    r = "GTAGS: Callers",
    t = "GTAGS: Text",
    e = "GTAGS: Egrep",
    f = "GTAGS: File",
    i = "GTAGS: Includes",
  }
  for suffix, expected in pairs(expected_maps) do
    local mapping = vim.fn.maparg("<leader>g" .. suffix, "n", false, true)
    assert(type(mapping) == "table" and mapping.desc,
      "missing map <leader>g" .. suffix)
    eq(expected, mapping.desc)
  end
end)

test("query maps dispatch through the reloaded adapter", function()
  local reloaded_adapter = require("gtags_adapter")
  local original_find = reloaded_adapter.find
  local dispatched_kind
  local ok, err = xpcall(function()
    reloaded_adapter.find = function(kind)
      dispatched_kind = kind
    end
    local mapping = vim.fn.maparg("<leader>gd", "n", false, true)
    mapping.callback()
    eq("g", dispatched_kind)
  end, debug.traceback)
  reloaded_adapter.find = original_find
  if not ok then error(err) end
end)

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

  local ok, err = xpcall(function()
    eq(true, adapter.update())
    eq(1, calls)
  end, debug.traceback)
  pcall(vim.api.nvim_del_user_command, "GutentagsUpdate")
  if not ok then error(err) end
end)

test("dispatches automatic updates before database metadata exists", function()
  local root = temp_root .. "/update-auto-unprepared"
  local source = root .. "/auto.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int auto_update_unprepared_symbol;" })
  edit(source)
  local calls = 0
  pcall(vim.api.nvim_del_user_command, "GutentagsUpdate")
  vim.api.nvim_create_user_command("GutentagsUpdate", function()
    calls = calls + 1
  end, {})

  local ok, err = xpcall(function()
    eq(nil, vim.b.gutentags_root)
    eq(nil, vim.b.gutentags_files)
    eq(true, adapter.update())
    eq(1, calls)
  end, debug.traceback)
  pcall(vim.api.nvim_del_user_command, "GutentagsUpdate")
  if not ok then error(err) end
end)

test("reports a throwing automatic update command", function()
  local root = temp_root .. "/update-auto-failure"
  local source = root .. "/auto.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int auto_update_failure_symbol;" })
  edit(source)
  vim.b.gutentags_root = root
  vim.b.gutentags_files = { gtags_cscope = temp_root .. "/cache/GTAGS" }
  pcall(vim.api.nvim_del_user_command, "GutentagsUpdate")
  vim.api.nvim_create_user_command("GutentagsUpdate", function()
    error("automatic update failed")
  end, {})

  local ok, err = xpcall(function()
    local before_notifications = #notifications
    local call_ok, result = pcall(adapter.update)
    eq(true, call_ok)
    eq(false, result)
    eq(before_notifications + 1, #notifications)
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    assert(notification.message:find("automatic update failed", 1, true))
  end, debug.traceback)
  pcall(vim.api.nvim_del_user_command, "GutentagsUpdate")
  if not ok then error(err) end
end)

test("runs one asynchronous global update per manual project", function()
  local root, source = manual_query_fixture("update-manual")
  edit(source)
  local old_system = vim.system
  local calls = {}
  local callbacks = {}
  vim.system = function(cmd, opts, cb)
    calls[#calls + 1] = { cmd = cmd, opts = opts }
    callbacks[#callbacks + 1] = cb
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
    eq(true, calls[1].opts.text)

    local before_completion = #notifications
    callbacks[1]({ code = 0, stdout = "", stderr = "" })
    assert(vim.wait(1000, function()
      return #notifications == before_completion + 1
    end))
    eq("Manual GTAGS update completed: " .. root, notifications[#notifications].message)

    eq(true, adapter.update())
    eq(2, #calls)
    local before_retry_completion = #notifications
    callbacks[2]({ code = 0, stdout = "", stderr = "" })
    assert(vim.wait(1000, function()
      return #notifications == before_retry_completion + 1
    end))
    eq(nil, _G.NvimGutentagsHybridState.manual_updates[root])
  end, debug.traceback)
  vim.system = old_system
  _G.NvimGutentagsHybridState.manual_updates[root] = nil
  if not ok then error(err) end
end)

test("does not build automatically inside a disabled project", function()
  local root = temp_root .. "/update-disabled"
  local source = root .. "/disabled.c"
  write(root .. "/.notags", {})
  write(source, { "int disabled_update_symbol;" })
  edit(source)

  eq(false, adapter.update())
  assert(notifications[#notifications].message:find("build GTAGS manually first", 1, true))
end)

test("reports a failed manual global update", function()
  local root, source = manual_query_fixture("update-failure")
  edit(source)
  local old_system = vim.system
  local callback
  vim.system = function(_, _, cb)
    callback = cb
    return { pid = 5678 }
  end

  local ok, err = xpcall(function()
    eq(true, adapter.update())
    local before_notifications = #notifications
    callback({ code = 2, stdout = "", stderr = "  database locked\n" })
    assert(vim.wait(1000, function()
      return #notifications == before_notifications + 1
    end))
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    eq("Manual GTAGS update failed (exit 2): database locked", notification.message)
  end, debug.traceback)
  vim.system = old_system
  _G.NvimGutentagsHybridState.manual_updates[root] = nil
  if not ok then error(err) end
end)

test("reports a signal-terminated manual update as a failure", function()
  local root, source = manual_query_fixture("update-signal-failure")
  edit(source)
  local old_system = vim.system
  local callback
  vim.system = function(_, _, cb)
    callback = cb
    return { pid = 6789 }
  end

  local ok, err = xpcall(function()
    eq(true, adapter.update())
    local before_notifications = #notifications
    callback({ code = 0, signal = 15, stdout = "", stderr = "" })
    assert(vim.wait(1000, function()
      return #notifications == before_notifications + 1
    end))
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    assert(notification.message:find("signal 15", 1, true))
    eq(nil, notification.message:find("update completed", 1, true))
    eq(nil, _G.NvimGutentagsHybridState.manual_updates[root])
  end, debug.traceback)
  vim.system = old_system
  _G.NvimGutentagsHybridState.manual_updates[root] = nil
  if not ok then error(err) end
end)

test("releases the manual update lock when global fails to start", function()
  local root, source = manual_query_fixture("update-launch-failure")
  edit(source)
  local old_system = vim.system
  local calls = 0
  local callback
  vim.system = function(_, _, cb)
    calls = calls + 1
    if calls == 1 then
      error("global launch failed")
    end
    callback = cb
    return { pid = 9012 }
  end

  local ok, err = xpcall(function()
    local before_notifications = #notifications
    local call_ok, result = pcall(adapter.update)
    eq(true, call_ok)
    eq(false, result)
    eq(before_notifications + 1, #notifications)
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    assert(notification.message:find("global launch failed", 1, true))

    eq(true, adapter.update())
    eq(2, calls)
    callback({ code = 0, stdout = "", stderr = "" })
    assert(vim.wait(1000, function()
      return notifications[#notifications].message:find("update completed", 1, true) ~= nil
    end))
  end, debug.traceback)
  vim.system = old_system
  _G.NvimGutentagsHybridState.manual_updates[root] = nil
  if not ok then error(err) end
end)

test("checks gtags only for automatic updates", function()
  local root = temp_root .. "/update-missing-gtags"
  local source = root .. "/auto.c"
  vim.fn.mkdir(root .. "/.git", "p")
  write(source, { "int auto_update_symbol;" })
  edit(source)
  local old_path = vim.env.PATH
  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    eq(false, adapter.update())
    local notification = notifications[#notifications]
    eq(vim.log.levels.ERROR, notification.level)
    eq("Missing indexing command: gtags", notification.message)
    eq(nil, notification.message:find("global", 1, true))
    eq(nil, notification.message:find("gtags-cscope", 1, true))
  end, debug.traceback)
  vim.env.PATH = old_path
  if not ok then error(err) end
end)

test("installs the leader-g update map", function()
  local current_adapter = require("gtags_adapter")
  local original_update = current_adapter.update
  local calls = 0
  local ok, err = xpcall(function()
    local mapping = vim.fn.maparg("<leader>gb", "n", false, true)
    assert(type(mapping) == "table" and mapping.desc, "missing map <leader>gb")
    eq("GTAGS: Update index", mapping.desc)
    eq(1, mapping.silent)

    current_adapter.update = function()
      calls = calls + 1
    end
    mapping.callback()
    eq(1, calls)
  end, debug.traceback)
  current_adapter.update = original_update
  if not ok then error(err) end
end)

test("blocks stale observer callbacks after reload invalidates state", function()
  local saved_state = _G.NvimGutentagsHybridState
  local ok, err = xpcall(function()
    local isolated_state = {
      automatic_transitions = {},
      manual_updates = {},
    }
    _G.NvimGutentagsHybridState = isolated_state
    package.loaded.gtags_adapter = nil
    require("gtags_adapter").setup()

    local root = temp_root .. "/stale-observer-reload"
    local source = root .. "/stale.c"
    local target = temp_root .. "/stale-observer-cache/GTAGS"
    vim.fn.mkdir(root .. "/.git", "p")
    write(source, { "int stale_observer_symbol;" })
    edit(source)
    eq(1, guard(source))
    local bufnr = vim.api.nvim_get_current_buf()
    vim.b.gutentags_root = root
    vim.b.gutentags_files = { gtags_cscope = target }
    eq(true, isolated_state.automatic_observers[bufnr].pending)

    isolated_state.automatic_metadata = "malformed"
    package.loaded.gtags_adapter = nil
    require("gtags_adapter").setup()
    eq(true, isolated_state.automatic_transitions_invalid)
    vim.wait(100)
    eq(nil, isolated_state.automatic_transitions[bufnr])
  end, debug.traceback)

  _G.NvimGutentagsHybridState = saved_state
  package.loaded.gtags_adapter = nil
  adapter = require("gtags_adapter")
  adapter.setup()
  if not ok then error(err) end
end)

test("keeps malformed transition roots blocked across reloads", function()
  local saved_state = _G.NvimGutentagsHybridState
  local old_path = vim.env.PATH

  local function assert_reload_blocked(seed, name)
    _G.NvimGutentagsHybridState = seed
    package.loaded.gtags_adapter = nil
    local isolated_adapter = require("gtags_adapter")
    isolated_adapter.setup()

    local root = temp_root .. "/malformed-" .. name
    local source = root .. "/malformed.c"
    local target = temp_root .. "/malformed-cache-" .. name .. "/GTAGS"
    vim.fn.mkdir(root .. "/.git", "p")
    write(root .. "/GTAGS", { "manual database" })
    write(source, { "int malformed_state_symbol;" })
    edit(source)
    vim.b.gutentags_hybrid_mode = "automatic"
    vim.b.gutentags_hybrid_root = root
    vim.b.gutentags_root = root
    vim.b.gutentags_files = { gtags_cscope = target }

    eq(false, isolated_adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
    eq(true, _G.NvimGutentagsHybridState.automatic_transitions_invalid)

    package.loaded.gtags_adapter = nil
    local reloaded_adapter = require("gtags_adapter")
    reloaded_adapter.setup()
    eq(true, _G.NvimGutentagsHybridState.automatic_transitions_invalid)
    eq(false, reloaded_adapter.update())
    vim.wait(100)
    eq("automatic", vim.b.gutentags_hybrid_mode)
  end

  local ok, err = xpcall(function()
    vim.env.PATH = "/definitely-missing"
    assert_reload_blocked({
      automatic_transitions = "malformed",
      manual_updates = {},
    }, "current")
    assert_reload_blocked({
      automatic_metadata = "malformed",
      automatic_transitions = {},
      manual_updates = {},
    }, "legacy")
  end, debug.traceback)

  vim.env.PATH = old_path
  _G.NvimGutentagsHybridState = saved_state
  package.loaded.gtags_adapter = nil
  adapter = require("gtags_adapter")
  adapter.setup()
  eq(nil, saved_state.automatic_transitions_invalid)
  if not ok then error(err) end
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
