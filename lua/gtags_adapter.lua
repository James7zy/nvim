local M = {}

local root_markers = {
  ".git", ".hg", ".svn", ".bzr", "_darcs", "_FOSSIL_", ".fslckout",
  ".root", ".project",
}

local state = _G.NvimGutentagsHybridState or {}
_G.NvimGutentagsHybridState = state

state.manual_updates = state.manual_updates or {}
local manual_updates = state.manual_updates

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

local function refreshed_files(before_files, after_files)
  local refreshed = {}
  if type(after_files) ~= "table" then
    return refreshed
  end
  for key, value in pairs(after_files) do
    local before_value
    if type(before_files) == "table" then
      before_value = before_files[key]
    end
    if not vim.deep_equal(before_value, value) then
      refreshed[key] = type(value) == "table" and vim.deepcopy(value) or value
    end
  end
  return refreshed
end

local function apply_context(context, hook_changes)
  local previous_mode = vim.b.gutentags_hybrid_mode
  local previous_root = vim.b.gutentags_hybrid_root
  local clear_unconditionally = context.mode == "disabled"
    or context.mode == "unconfigured"
  local must_clear = clear_unconditionally
    or previous_root ~= nil and previous_root ~= context.root
    or (context.mode == "automatic" and previous_mode == "manual")
  if must_clear then
    if clear_unconditionally or not (hook_changes and hook_changes.gutentags_root) then
      vim.b.gutentags_root = nil
    end
    local files = hook_changes and hook_changes.gutentags_files
    if clear_unconditionally or not files or not next(files) then
      vim.b.gutentags_files = nil
    else
      vim.b.gutentags_files = files
    end
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

local function hybrid_guard(path, hook_changes)
  local context = classify(path)
  apply_context(context, hook_changes)
  return (context.mode == "manual" or context.mode == "disabled") and 0 or 1
end

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

local query_kinds = {
  g = true, s = true, c = true, t = true, e = true, f = true, i = true,
}

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
      require("gtags_adapter").find(value[1])
    end, { silent = true, desc = "GTAGS: " .. value[2] })
  end
end

function M.find(kind)
  if not query_kinds[kind] then
    notify("不支持的 GTAGS 查询类型: " .. tostring(kind), vim.log.levels.ERROR)
    return false
  end
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
  local shell_error = vim.v.shell_error
  if not ok then
    notify("GTAGS 查询失败；数据库: " .. context.database .. "；请查看 :messages",
      vim.log.levels.ERROR)
    return false
  end
  if shell_error ~= 0 then
    notify("GTAGS 查询失败（退出码 " .. shell_error .. "）；数据库: "
      .. context.database .. "；请查看 :messages", vim.log.levels.ERROR)
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
  if not loaded or type(fzf) ~= "table" or type(fzf.quickfix) ~= "function" then
    notify("fzf-lua 不可用", vim.log.levels.ERROR)
    return false
  end
  local opened = pcall(fzf.quickfix, { valid_only = true })
  if not opened then
    notify("fzf-lua quickfix 打开失败", vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.setup()
  if not state.configured then
    state.previous_init_hook = vim.g.gutentags_init_user_func
  end

  _G.NvimGutentagsHybridGuard = function(path)
    if type(state.previous_init_hook) == "string"
        and state.previous_init_hook ~= ""
        and state.previous_init_hook ~= "GutentagsHybridGuard" then
      local before_root = vim.b.gutentags_root
      local before_files = vim.b.gutentags_files
      if type(before_files) == "table" then
        before_files = vim.deepcopy(before_files)
      end
      local ok, allowed = pcall(vim.fn.call, state.previous_init_hook, { path })
      if not ok or vim.fn.empty(allowed) == 1 then
        return 0
      end
      return hybrid_guard(path, {
        gutentags_files = refreshed_files(before_files, vim.b.gutentags_files),
        gutentags_root = not vim.deep_equal(before_root, vim.b.gutentags_root),
      })
    end
    return hybrid_guard(path)
  end

  if state.configured then
    return
  end
  vim.cmd([[
    function! GutentagsHybridGuard(path) abort
      return v:lua.NvimGutentagsHybridGuard(a:path)
    endfunction
  ]])
  vim.g.gutentags_init_user_func = "GutentagsHybridGuard"
  setup_keymaps()
  state.configured = true
end

return M
