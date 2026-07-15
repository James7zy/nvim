# Gutentags English Runtime UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every adapter-owned Chinese Gutentags runtime message and keymap description with English while preserving backend diagnostics and all behavior.

**Architecture:** Keep the existing inline-message design in `lua/gtags_adapter.lua`; do not add an i18n layer or message catalog. Tests define the exact English contract first, then production literals are changed mechanically without touching control flow.

**Tech Stack:** Neovim 0.12 Lua, native headless Lua tests, real `vim-gutentags`/`gutentags_plus` integration, GNU GLOBAL.

---

## File Map

- Modify `lua/gtags_adapter.lua`: English runtime notifications, context errors, and `<leader>g*` descriptions.
- Modify `tests/gtags_adapter_spec.lua`: exact English unit expectations and keymap-description contract.
- Modify `tests/gtags_integration.lua`: English retry and empty-result assertions.
- Do not modify `README.md`, plugin comments, dependencies, lockfiles, or backend diagnostic payloads.

### Task 1: Define The English UI Contract In Tests

**Files:**
- Modify: `tests/gtags_adapter_spec.lua`
- Modify: `tests/gtags_integration.lua`

- [ ] **Step 1: Replace the unit-test message expectations**

Make these exact assertion changes in `tests/gtags_adapter_spec.lua`:

| Existing assertion text | English assertion text |
|---|---|
| `稍后重试` | `try again shortly` |
| `未找到` | `No matches` |
| `查询失败` | `query failed` |
| `查询类型` | `query type` |
| `手动索引正在更新` | `manual index is being updated` |
| `正在生成或更新` | `building or updating the index` |
| `Gutentags 尚未为当前项目准备数据库` | `Gutentags has not prepared the current project's database yet` |
| `手动 GTAGS 更新完成: ` | `Manual GTAGS update completed: ` |
| `手动生成 GTAGS` | `build GTAGS manually first` |
| `手动 GTAGS 更新失败 (exit 2): database locked` | `Manual GTAGS update failed (exit 2): database locked` |
| `更新完成` | `update completed` |
| `缺少索引命令: gtags` | `Missing indexing command: gtags` |

The exact expectations must read:

```lua
eq("Gutentags has not prepared the current project's database yet",
  notification.message)
eq("Manual GTAGS update completed: " .. root,
  notifications[#notifications].message)
eq("Manual GTAGS update failed (exit 2): database locked",
  notification.message)
eq("Missing indexing command: gtags", notification.message)
```

Keep the backend payload expectations unchanged:

```lua
assert(notifications[#notifications].message:find("GTAGS corrupted", 1, true))
eq("Manual GTAGS update failed (exit 2): database locked",
  notification.message)
```

- [ ] **Step 2: Strengthen the keymap description test**

Replace the prefix-only keymap assertion with exact descriptions:

```lua
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
  eq(expected, mapping.desc)
end
eq("GTAGS: Update index",
  vim.fn.maparg("<leader>gb", "n", false, true).desc)
```

Retain the existing assertions that each mapping dispatches through the reloaded adapter.

- [ ] **Step 3: Replace the integration-test message expectations**

In `tests/gtags_integration.lua`, use these assertions:

```lua
assert(notifications[#notifications]:find("try again shortly", 1, true),
  "transition failure did not request a retry")
```

For the corrupt-database diagnostic, keep checking the raw backend text and change only the negative empty-result assertion:

```lua
assert(not failure:find("No matches", 1, true),
  "corrupt GTAGS query was reported as an empty result")
```

- [ ] **Step 4: Run the adapter suite to verify RED**

Run:

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
```

Expected: exit nonzero. Failures must show the adapter still emitted Chinese messages or Chinese keymap descriptions. Existing indexing, query routing, and state-transition tests must continue reaching their assertions rather than failing with Lua errors.

### Task 2: Translate Adapter-Owned Runtime UI

**Files:**
- Modify: `lua/gtags_adapter.lua`
- Test: `tests/gtags_adapter_spec.lua`
- Test: `tests/gtags_integration.lua`

- [ ] **Step 1: Translate context and transition messages**

Use these exact English literals:

```lua
local transition_retry_message =
  "Gutentags is still finalizing the automatic index; try again shortly"

"Current buffer is not a queryable regular file"
context.root .. " contains .notags; build GTAGS manually first"
"Project root not found; create .root in the project root"
```

- [ ] **Step 2: Translate keymap descriptions**

Use this map table and update description:

```lua
local maps = {
  d = { "g", "Definition" },
  s = { "s", "Symbol/References" },
  r = { "c", "Callers" },
  t = { "t", "Text" },
  e = { "e", "Egrep" },
  f = { "f", "File" },
  i = { "i", "Includes" },
}

{ silent = true, desc = "GTAGS: Update index" }
```

- [ ] **Step 3: Translate query messages**

Replace the adapter-owned query strings with these exact values:

```lua
"Unsupported GTAGS query type: " .. tostring(kind)
"Gutentags has not prepared the current project's database yet"
"Missing query commands: " .. table.concat(missing, ", ")
"Gutentags is building or updating the index; try the query again shortly"
"The manual index is being updated; try the query again shortly"
"GTAGS database is not ready: " .. context.database
"No queryable symbol under the cursor"
"GscopeFind command is unavailable"
"GTAGS query failed; database: " .. context.database .. "; see :messages"
"GTAGS query failed (exit " .. shell_error .. "); database: "
  .. context.database .. "; see :messages"
"No matches: " .. term
detail .. "; database: " .. context.database
"fzf-lua is unavailable"
"Failed to open the fzf-lua quickfix picker"
```

Do not transform `errors[1]`; it is the raw `gtags-cscope` quickfix diagnostic.

- [ ] **Step 4: Translate update messages**

Use these exact values:

```lua
"Missing indexing command: gtags"
"Current buffer has no GutentagsUpdate command"
"Failed to start Gutentags update: " .. tostring(command_error)
"Build GTAGS manually first"
"Missing index update command: global"
"The manual index is already being updated"
"Manual GTAGS update completed: " .. context.root
"Manual GTAGS update failed (" .. status .. ")"
"Failed to start manual GTAGS update: " .. tostring(launch_error)
```

Continue appending `stderr` unchanged to the manual-update failure message.

- [ ] **Step 5: Run the adapter suite to verify GREEN**

Run:

```bash
nvim --headless -u NONE -l tests/gtags_adapter_spec.lua
```

Expected: exit 0 with `All gtags adapter tests passed`.

- [ ] **Step 6: Run the real integration suite**

Run:

```bash
nvim --headless -l tests/gtags_integration.lua
```

Expected: exit 0 with `Gutentags integration test passed`. Output may contain English adapter retry/update notifications and raw English backend diagnostics.

### Task 3: Verify Scope And Compatibility

**Files:**
- Verify: `lua/gtags_adapter.lua`
- Verify: `tests/gtags_adapter_spec.lua`
- Verify: `tests/gtags_integration.lua`

- [ ] **Step 1: Confirm the adapter contains no Chinese characters**

Run:

```bash
rg -n '[一-龥]' lua/gtags_adapter.lua
```

Expected: exit 1 with no output.

- [ ] **Step 2: Confirm backend diagnostic tests remain present**

Run:

```bash
rg -n 'GTAGS corrupted|database locked' tests/gtags_adapter_spec.lua tests/gtags_integration.lua
```

Expected: matches for both raw diagnostic payloads.

- [ ] **Step 3: Run startup and diff checks**

Run:

```bash
nvim --headless "+lua assert(vim.fn.exists(':GscopeFind') == 2)" \
  "+lua assert(vim.fn.has('cscope') == 0)" +qa
git diff --check
git status --short
```

Expected: both commands exit 0. Before committing, status lists only:

```text
 M lua/gtags_adapter.lua
 M tests/gtags_adapter_spec.lua
 M tests/gtags_integration.lua
?? docs/superpowers/plans/2026-07-15-gutentags-english-ui.md
```

- [ ] **Step 4: Review the final diff for behavioral changes**

Run:

```bash
git diff --stat
git diff -- lua/gtags_adapter.lua tests/gtags_adapter_spec.lua tests/gtags_integration.lua
```

Expected: only string literals and message assertions/descriptions change. No condition, return value, command, notification level, key binding, dependency, or README line changes.

- [ ] **Step 5: Commit the implementation**

```bash
git add lua/gtags_adapter.lua tests/gtags_adapter_spec.lua \
  tests/gtags_integration.lua docs/superpowers/plans/2026-07-15-gutentags-english-ui.md
git commit -m "refactor(gtags): use English runtime messages"
```
