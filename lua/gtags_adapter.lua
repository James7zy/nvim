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

local function automatic_update_running(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end
  local ok, jobs = pcall(vim.api.nvim_buf_call, bufnr, function()
    return vim.fn["gutentags#inprogress"]()
  end)
  return not ok or type(jobs) ~= "table"
    or vim.tbl_contains(jobs, "gtags_cscope")
end

local function detach_gutentags_write_hook(bufnr)
  local group_name = "gutentags_buffer_" .. bufnr
  -- Legacy Vimscript autocmds have no API id, so clear Gutentags' owned tuple.
  local autocmds = vim.api.nvim_get_autocmds({
    event = "BufWritePost",
    buffer = bufnr,
  })
  for _, autocmd in ipairs(autocmds) do
    if autocmd.group_name == group_name then
      vim.api.nvim_clear_autocmds({
        group = autocmd.group,
        event = "BufWritePost",
        buffer = bufnr,
      })
      return
    end
  end
end

local transition_retry_message =
  "Gutentags 自动索引尚未安全退出；请稍后重试"

local function apply_context(bufnr, context, hook_changes)
  local buffer = vim.b[bufnr]
  local previous_mode = buffer.gutentags_hybrid_mode
  local previous_root = buffer.gutentags_hybrid_root
  if previous_mode == "automatic" and context.mode ~= "automatic"
      and automatic_update_running(bufnr) then
    return false, transition_retry_message
  end
  if context.mode ~= "automatic" then
    detach_gutentags_write_hook(bufnr)
  end
  local clear_unconditionally = context.mode == "disabled"
    or context.mode == "unconfigured"
  local must_clear = clear_unconditionally
    or previous_root ~= nil and previous_root ~= context.root
    or (context.mode == "automatic" and previous_mode == "manual")
  if must_clear then
    if clear_unconditionally or not (hook_changes and hook_changes.gutentags_root) then
      buffer.gutentags_root = nil
    end
    local files = hook_changes and hook_changes.gutentags_files
    if clear_unconditionally or not files or not next(files) then
      buffer.gutentags_files = nil
    else
      buffer.gutentags_files = files
    end
  end
  buffer.gutentags_hybrid_mode = context.mode
  buffer.gutentags_hybrid_root = context.root
  if context.mode ~= "manual" then
    return true
  end
  local files = type(buffer.gutentags_files) == "table"
      and vim.deepcopy(buffer.gutentags_files) or {}
  files.gtags_cscope = context.database
  buffer.gutentags_root = context.root
  buffer.gutentags_files = files
  return true
end

local function hybrid_guard(bufnr, path, hook_changes)
  local context = classify(path)
  local applied = apply_context(bufnr, context, hook_changes)
  if not applied then
    return 1
  end
  return (context.mode == "manual" or context.mode == "disabled") and 0 or 1
end

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "GTAGS" })
end

local function schedule_context_transition(bufnr, path, context)
  local buffer = vim.b[bufnr]
  local snapshot = {
    gutentags_files = type(buffer.gutentags_files) == "table"
        and vim.deepcopy(buffer.gutentags_files) or buffer.gutentags_files,
    gutentags_hybrid_mode = buffer.gutentags_hybrid_mode,
    gutentags_hybrid_root = buffer.gutentags_hybrid_root,
    gutentags_root = buffer.gutentags_root,
  }
  vim.schedule(function()
    if not vim.api.nvim_buf_is_valid(bufnr)
        or vim.api.nvim_buf_get_name(bufnr) ~= path then
      return
    end
    local current = vim.b[bufnr]
    if current.gutentags_hybrid_mode ~= snapshot.gutentags_hybrid_mode
        or current.gutentags_hybrid_root ~= snapshot.gutentags_hybrid_root
        or current.gutentags_root ~= snapshot.gutentags_root
        or not vim.deep_equal(current.gutentags_files,
          snapshot.gutentags_files)
        or not vim.deep_equal(classify(path), context) then
      return
    end
    apply_context(bufnr, context)
  end)
end

local function current_context()
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or vim.bo[bufnr].buftype ~= "" or vim.fn.filereadable(path) ~= 1 then
    return nil, "当前 buffer 不是可查询的普通文件"
  end
  local context = classify(path)
  if vim.b[bufnr].gutentags_hybrid_mode == "automatic"
      and context.mode ~= "automatic" then
    schedule_context_transition(bufnr, path, context)
    return nil, transition_retry_message
  end
  local applied, apply_error = apply_context(bufnr, context)
  if not applied then
    return nil, apply_error
  end
  context.bufnr = bufnr
  if context.mode == "automatic" then
    local files = vim.b[bufnr].gutentags_files
    context.root = vim.b[bufnr].gutentags_root or context.root
    context.database = type(files) == "table" and files.gtags_cscope or nil
  end
  if context.mode == "disabled" then
    return context, context.root .. " 包含 .notags；请先手动生成 GTAGS"
  end
  if context.mode == "unconfigured" then
    return context, "找不到项目根；请在项目根创建 .root"
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
  vim.keymap.set("n", "<leader>gb", function()
    require("gtags_adapter").update()
  end, { silent = true, desc = "GTAGS: 更新索引" })
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
  if context.mode == "disabled" or context.mode == "unconfigured" then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
  if context.mode == "automatic"
      and (type(context.database) ~= "string" or context.database == "") then
    notify("Gutentags 尚未为当前项目准备数据库", vim.log.levels.WARN)
    return false
  end
  local missing = missing_tools({ "global", "gtags-cscope" })
  if #missing > 0 then
    notify("缺少查询命令: " .. table.concat(missing, ", "), vim.log.levels.ERROR)
    return false
  end
  if context.mode == "automatic" and automatic_update_running(context.bufnr) then
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

function M.update()
  local context, context_error = current_context()
  if not context then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
  if context.mode == "disabled" then
    notify(context_error, vim.log.levels.WARN)
    return false
  end
  if context.mode == "unconfigured" then
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
    local ok, command_error = pcall(vim.api.nvim_cmd, {
      cmd = "GutentagsUpdate",
    }, {})
    if not ok then
      notify("Gutentags 更新启动失败: " .. tostring(command_error), vim.log.levels.ERROR)
      return false
    end
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
  local launched, launch_error = pcall(vim.system, { "global", "-u" }, {
    cwd = context.root,
    env = { GTAGSROOT = context.root, GTAGSDBPATH = context.root },
    text = true,
  }, function(result)
    manual_updates[context.root] = nil
    vim.schedule(function()
      local signal = result.signal or 0
      if result.code == 0 and signal == 0 then
        notify("手动 GTAGS 更新完成: " .. context.root)
      else
        local stderr = vim.trim(result.stderr or "")
        local status = signal ~= 0 and ("signal " .. signal)
          or ("exit " .. result.code)
        notify("手动 GTAGS 更新失败 (" .. status .. ")"
          .. (stderr ~= "" and (": " .. stderr) or ""), vim.log.levels.ERROR)
      end
    end)
  end)
  if not launched then
    manual_updates[context.root] = nil
    notify("手动 GTAGS 更新启动失败: " .. tostring(launch_error), vim.log.levels.ERROR)
    return false
  end
  return true
end

function M.setup()
  if not state.configured then
    state.previous_init_hook = vim.g.gutentags_init_user_func
  end

  _G.NvimGutentagsHybridGuard = function(path)
    local target_bufnr = vim.api.nvim_get_current_buf()
    if type(state.previous_init_hook) == "string"
        and state.previous_init_hook ~= ""
        and state.previous_init_hook ~= "GutentagsHybridGuard" then
      local before_root = vim.b[target_bufnr].gutentags_root
      local before_files = vim.b[target_bufnr].gutentags_files
      if type(before_files) == "table" then
        before_files = vim.deepcopy(before_files)
      end
      local ok, allowed = pcall(vim.api.nvim_buf_call, target_bufnr, function()
        return vim.fn.call(state.previous_init_hook, { path })
      end)
      if not ok or not vim.api.nvim_buf_is_valid(target_bufnr)
          or vim.fn.empty(allowed) == 1 then
        return 0
      end
      local after_files = vim.b[target_bufnr].gutentags_files
      return hybrid_guard(target_bufnr, path, {
        gutentags_files = refreshed_files(before_files, after_files),
        gutentags_root = not vim.deep_equal(
          before_root, vim.b[target_bufnr].gutentags_root),
      })
    end
    return hybrid_guard(target_bufnr, path)
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
