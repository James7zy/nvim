  #!/usr/bin/env bash
  # Claude Code statusline: model [effort] [bar] %  •  5h N% (resets HH:MM)
  input=$(cat)

  model=$(echo "$input"    | jq -r '.model.display_name // "Claude"')
  effort=$(echo "$input"   | jq -r '.effort.level // empty')
  used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

  rl_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
  rl_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

  C_RESET=$'\033[0m'; C_MODEL=$'\033[1;36m'; C_EFFORT=$'\033[0;35m'
  C_BAR=$'\033[0;32m'; C_DIM=$'\033[0;90m'

  # model
  printf "%s%s%s" "$C_MODEL" "$model" "$C_RESET"

  # effort
  [ -n "$effort" ] && printf " %s[%s]%s" "$C_EFFORT" "$effort" "$C_RESET"

  # progress bar (20 wide; at least 1 filled cell when >0%)
  if [ -n "$used_pct" ]; then
    pct=$(printf '%.0f' "$used_pct")
    width=20; filled=$(( pct * width / 100 ))
    [ "$pct" -gt 0 ] && [ "$filled" -lt 1 ] && filled=1
    [ "$filled" -gt "$width" ] && filled=$width
    bar=""
    for ((i=0;i<filled;i++)); do bar+="█"; done
    for ((i=filled;i<width;i++)); do bar+="░"; done
    printf " %s[%s]%s %s%d%%%s" "$C_BAR" "$bar" "$C_RESET" "$C_DIM" "$pct" "$C_RESET"
  fi

  # 5h rate limit:  • 5h 73% (resets 21:10)
  if [ -n "$rl_pct" ] && [ -n "$rl_reset" ]; then
    rfmt=$(date -d "@$rl_reset" '+%H:%M' 2>/dev/null || echo "$rl_reset")
    printf " %s• 5h %d%% (resets %s)%s" "$C_DIM" "$rl_pct" "$rfmt" "$C_RESET"
  fi
