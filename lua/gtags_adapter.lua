local M = {}

local root_markers = {
  ".git", ".hg", ".svn", ".bzr", "_darcs", "_FOSSIL_", ".fslckout",
  ".root", ".project",
}

local state = _G.NvimGutentagsHybridState or {}
_G.NvimGutentagsHybridState = state

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
  local previous_root = vim.b.gutentags_hybrid_root
  local must_clear = previous_root ~= context.root
    or context.mode == "disabled"
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
  if state.configured then
    return
  end
  state.configured = true
  state.previous_init_hook = vim.g.gutentags_init_user_func

  _G.NvimGutentagsHybridGuard = function(path)
    if type(state.previous_init_hook) == "string"
        and state.previous_init_hook ~= ""
        and state.previous_init_hook ~= "GutentagsHybridGuard" then
      local ok, allowed = pcall(vim.fn.call, state.previous_init_hook, { path })
      if not ok or vim.fn.empty(allowed) == 1 then
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
