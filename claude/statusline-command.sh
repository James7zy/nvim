#!/usr/bin/env bash
# Claude Code statusline (2 lines)
#   L1: model (ctx) [effort] [bar] % tokens • 5h N% (resets HH:MM) • 7d N% (resets MM/DD HH:MM)
#   L2: dir  branch* | +added -removed | ⏱ duration | $cost
input=$(cat)

j() { echo "$input" | jq -r "$1"; }

model=$(j '.model.display_name // "Claude"')
context_size=$(j '.context_window.context_window_size // empty')
effort=$(j '.effort.level // empty')
used_pct=$(j '.context_window.used_percentage // empty')
used_tokens=$(j '(.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)')

rl5_pct=$(j '.rate_limits.five_hour.used_percentage // empty')
rl5_reset=$(j '.rate_limits.five_hour.resets_at // empty')
rl7_pct=$(j '.rate_limits.seven_day.used_percentage // empty')
rl7_reset=$(j '.rate_limits.seven_day.resets_at // empty')

cwd=$(j '.workspace.current_dir // .cwd // empty')
lines_add=$(j '.cost.total_lines_added // empty')
lines_del=$(j '.cost.total_lines_removed // empty')
duration_ms=$(j '.cost.total_duration_ms // empty')
cost_usd=$(j '.cost.total_cost_usd // empty')

C_RESET=$'\033[0m'; C_MODEL=$'\033[1;36m'; C_EFFORT=$'\033[0;35m'
C_DIM=$'\033[0;90m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[0;33m'; C_RED=$'\033[0;31m'
C_BLUE=$'\033[0;34m'; C_BRANCH=$'\033[0;35m'

# color by percentage: <60 green, 60-79 yellow, >=80 red
pct_color() {
  local p=$1
  if [ "$p" -ge 80 ]; then echo "$C_RED"
  elif [ "$p" -ge 60 ]; then echo "$C_YELLOW"
  else echo "$C_GREEN"; fi
}

# ---------- line 1 ----------
printf "%s%s%s" "$C_MODEL" "$model" "$C_RESET"

if [ -n "$context_size" ]; then
  if [ "$context_size" -ge 1000000 ]; then ctx_fmt="$((context_size / 1000000))M"
  elif [ "$context_size" -ge 1000 ]; then ctx_fmt="$((context_size / 1000))K"
  else ctx_fmt="$context_size"; fi
  printf " %s(%s context)%s" "$C_DIM" "$ctx_fmt" "$C_RESET"
fi

[ -n "$effort" ] && printf " %s[%s]%s" "$C_EFFORT" "$effort" "$C_RESET"

# context progress bar (20 wide; at least 1 filled cell when >0%)
if [ -n "$used_pct" ]; then
  pct=$(printf '%.0f' "$used_pct")
  width=20; filled=$(( pct * width / 100 ))
  [ "$pct" -gt 0 ] && [ "$filled" -lt 1 ] && filled=1
  [ "$filled" -gt "$width" ] && filled=$width
  bar=""
  for ((i=0;i<filled;i++)); do bar+="█"; done
  for ((i=filled;i<width;i++)); do bar+="░"; done
  c=$(pct_color "$pct")
  printf " %s[%s]%s %s%d%%%s" "$c" "$bar" "$C_RESET" "$c" "$pct" "$C_RESET"
fi

if [ -n "$used_tokens" ] && [ "$used_tokens" -gt 0 ]; then
  used_k=$(( used_tokens / 1000 ))
  if [ -n "$context_size" ] && [ "$context_size" -ge 1000 ]; then max_k=$(( context_size / 1000 )); else max_k=1000; fi
  printf " %s%dk / %dk tokens%s" "$C_DIM" "$used_k" "$max_k" "$C_RESET"
fi

# rate limits:  • 5h 73% (resets 21:10)  • 7d 40% (resets 11/25 14:00)
if [ -n "$rl5_pct" ]; then
  p=$(printf '%.0f' "$rl5_pct"); c=$(pct_color "$p")
  printf " %s•%s %s5h %d%%%s" "$C_DIM" "$C_RESET" "$c" "$p" "$C_RESET"
  if [ -n "$rl5_reset" ]; then
    rfmt=$(date -d "@$rl5_reset" '+%H:%M' 2>/dev/null || echo "$rl5_reset")
    printf " %s(resets %s)%s" "$C_DIM" "$rfmt" "$C_RESET"
  fi
fi
if [ -n "$rl7_pct" ]; then
  p=$(printf '%.0f' "$rl7_pct"); c=$(pct_color "$p")
  printf " %s•%s %s7d %d%%%s" "$C_DIM" "$C_RESET" "$c" "$p" "$C_RESET"
  if [ -n "$rl7_reset" ]; then
    rfmt=$(date -d "@$rl7_reset" '+%m/%d %H:%M' 2>/dev/null || echo "$rl7_reset")
    printf " %s(resets %s)%s" "$C_DIM" "$rfmt" "$C_RESET"
  fi
fi

# ---------- line 2 ----------
parts=()

if [ -n "$cwd" ]; then
  dir="${cwd/#$HOME/\~}"
  seg="${C_BLUE}${dir}${C_RESET}"
  if branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short -q HEAD 2>/dev/null \
              || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null); then
    dirty=""
    [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | head -1)" ] && dirty="*"
    seg+="  ${C_BRANCH}${branch}${dirty}${C_RESET}"
  fi
  parts+=("$seg")
fi

if [ -n "$lines_add" ] || [ -n "$lines_del" ]; then
  parts+=("${C_GREEN}+${lines_add:-0}${C_RESET} ${C_RED}-${lines_del:-0}${C_RESET}")
fi

if [ -n "$duration_ms" ]; then
  s=$(( ${duration_ms%.*} / 1000 ))
  if [ "$s" -ge 3600 ]; then d=$(printf '%dh%02dm' $((s/3600)) $((s%3600/60)))
  elif [ "$s" -ge 60 ]; then d="$((s/60))m"
  else d="${s}s"; fi
  parts+=("${C_DIM}⏱ ${d}${C_RESET}")
fi

if [ -n "$cost_usd" ]; then
  parts+=("${C_DIM}\$$(printf '%.2f' "$cost_usd")${C_RESET}")
fi

if [ "${#parts[@]}" -gt 0 ]; then
  out=""
  for i in "${!parts[@]}"; do
    [ "$i" -gt 0 ] && out+="${C_DIM} | ${C_RESET}"
    out+="${parts[$i]}"
  done
  printf "\n%s" "$out"
fi
