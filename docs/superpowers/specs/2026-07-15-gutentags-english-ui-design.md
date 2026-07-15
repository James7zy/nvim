# Gutentags English Runtime UI Design

Date: 2026-07-15

Status: Approved

## Goal

Convert every hardcoded Gutentags/GTAGS user-facing runtime message and keymap
description to English. The change improves terminal and locale compatibility
without changing indexing, query, update, or transition behavior.

## Scope

The implementation changes only:

- `lua/gtags_adapter.lua`: runtime notifications, context errors, query/update
  status messages, and `<leader>g*` descriptions.
- `tests/gtags_adapter_spec.lua`: unit expectations for the English messages.
- `tests/gtags_integration.lua`: integration assertions for retry and empty-result
  wording.

The following remain unchanged:

- The Chinese README and source comments.
- UI text belonging to other plugins or general Neovim configuration.
- Dynamic diagnostics emitted by `gtags-cscope`, `global`, Neovim, or the shell.
- Notification levels, titles, control flow, return values, and key bindings.

## Approach

Replace existing inline Chinese literals with concise English literals. A
message catalog or general localization layer is not introduced because only
one locale is required and the current adapter already owns these messages.

Message style:

- Use short action-oriented sentences, for example `Try again shortly` and
  `Build GTAGS manually first`.
- Use `Current buffer`, `Project root`, `Database`, `query`, and `index`
  consistently.
- Keep command and plugin names exact: `GTAGS`, `GutentagsUpdate`,
  `GscopeFind`, `fzf-lua`, `global`, and `gtags-cscope`.
- Append external diagnostics verbatim after an English prefix or suffix.
- Use ASCII punctuation in all adapter-owned messages.

Keymap descriptions remain prefixed with `GTAGS:` and use English action
names such as `Definition`, `Symbol/References`, `Callers`, `Text`, `File`,
`Includes`, and `Update index`.

## Error And Diagnostic Handling

Only adapter-owned framing is translated. A backend message such as
`GTAGS corrupted` or `database locked` must remain byte-for-byte unchanged in
the final notification. Database paths and exit/signal values are also
preserved.

No new fallback behavior is added. A translation must not alter whether an
operation returns success, opens fzf-lua, jumps directly, or reports a warning
or error.

## Test Strategy

Follow RED/GREEN:

1. Change existing assertions to the approved English wording and add coverage
   where a user-visible string is not currently asserted.
2. Run the adapter suite and confirm it fails only because production still
   emits Chinese text.
3. Translate the production literals and keymap descriptions.
4. Run the adapter and real integration suites.
5. Verify `lua/gtags_adapter.lua` contains no Chinese characters while README
   and comments outside the adapter remain untouched.

The final diff must contain no behavioral or dependency changes.
